import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_embedder/flutter_embedder.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'scam_model.dart';
import 'scam_prediction.dart';

class AegisOnnxScamModel implements ScamModel {
  AegisOnnxScamModel({
    this.modelAsset = _defaultModelAsset,
    this.tokenizerAsset = _defaultTokenizerAsset,
    this.tokenizerConfigAsset = _defaultTokenizerConfigAsset,
  });

  static const String modelVersion = 'aegis-distilbert-multilingual-int8-v1';
  static const int maxSequenceLength = 128;
  static const String _defaultModelAsset =
      'assets/ml/aegis/model_int8_final.onnx';
  static const String _defaultTokenizerAsset =
      'assets/ml/aegis/tokenizer.json';
  static const String _defaultTokenizerConfigAsset =
      'assets/ml/aegis/tokenizer_config.json';

  final String modelAsset;
  final String tokenizerAsset;
  final String tokenizerConfigAsset;

  Future<void>? _initialization;
  HfTokenizer? _tokenizer;
  OrtSession? _session;
  Future<void> _inferenceQueue = Future<void>.value();
  bool _disposed = false;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(
        const ScamModelException('The model has been disposed.'),
      );
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await initFlutterEmbedder();
      final tokenizerConfig = jsonDecode(
        await rootBundle.loadString(tokenizerConfigAsset),
      );
      if (tokenizerConfig is! Map<String, dynamic>) {
        throw const ScamModelException('Tokenizer config is not a JSON object.');
      }

      final tokenizer = await HfTokenizer.fromAsset(tokenizerAsset);
      final runtime = OnnxRuntime();
      final session = await runtime.createSessionFromAsset(
        modelAsset,
        options: OrtSessionOptions(
          intraOpNumThreads: 1,
          interOpNumThreads: 1,
          providers: [OrtProvider.CPU],
        ),
      );

      if (!session.inputNames.contains('input_ids') ||
          !session.inputNames.contains('attention_mask') ||
          session.outputNames.length != 1 ||
          !session.outputNames.contains('logits')) {
        await session.close();
        throw const ScamModelException('ONNX graph contract does not match.');
      }

      _tokenizer = tokenizer;
      _session = session;
    } catch (error) {
      _initialization = null;
      if (error is ScamModelException) rethrow;
      throw ScamModelException('Unable to initialize ONNX model.', error);
    }
  }

  @override
  Future<ScamPrediction> predict(String text) {
    if (text.trim().isEmpty) {
      return Future<ScamPrediction>.error(
        const ScamModelException('Text must not be empty or whitespace-only.'),
      );
    }
    return _runExclusive(() async {
      await initialize();
      final tokenizer = _tokenizer;
      final session = _session;
      if (tokenizer == null || session == null) {
        throw const ScamModelException('ONNX model is unavailable.');
      }

      final encoded = tokenizer.encode(text, addSpecialTokens: true);
      if (encoded.ids.isEmpty || encoded.ids.length > maxSequenceLength) {
        throw const ScamModelException('Tokenizer returned an invalid sequence.');
      }

      final ids = Int64List.fromList(encoded.ids.map((id) => id.toInt()).toList());
      final mask = Int64List.fromList(
        encoded.attentionMask.map((value) => value.toInt()).toList(),
      );
      final inputShape = <int>[1, ids.length];
      OrtValue? inputIds;
      OrtValue? attentionMask;
      Map<String, OrtValue>? outputs;
      try {
        inputIds = await OrtValue.fromList(ids, inputShape);
        attentionMask = await OrtValue.fromList(mask, inputShape);
        if (inputIds.dataType != OrtDataType.int64 ||
            attentionMask.dataType != OrtDataType.int64 ||
            inputShape[0] != 1 ||
            inputShape[1] > maxSequenceLength) {
          throw const ScamModelException('ONNX input tensor contract mismatch.');
        }
        outputs = await session.run({
          'input_ids': inputIds,
          'attention_mask': attentionMask,
        });
        final output = outputs['logits'];
        if (output == null ||
          output.dataType != OrtDataType.float32 ||
          output.shape.length != 2 ||
          output.shape[0] != 1 ||
          output.shape[1] != 2) {
          throw const ScamModelException('ONNX logits output has an invalid shape.');
        }
        final values = await output.asFlattenedList();
        if (values.length != 2) {
          throw const ScamModelException('ONNX logits output has an invalid size.');
        }
        final logits = values.map((value) => (value as num).toDouble()).toList();
        if (logits.any((value) => !value.isFinite)) {
          throw const ScamModelException('ONNX logits are not finite.');
        }
        return _prediction(logits, encoded.tokens, ids, mask, inputShape);
      } catch (error) {
        if (error is ScamModelException) rethrow;
        throw ScamModelException('ONNX inference failed.', error);
      } finally {
        await inputIds?.dispose();
        await attentionMask?.dispose();
        if (outputs != null) {
          for (final output in outputs.values) {
            await output.dispose();
          }
        }
      }
    });
  }

  ScamPrediction _prediction(
    List<double> logits,
    List<String> tokens,
    Int64List inputIds,
    Int64List attentionMask,
    List<int> inputShape,
  ) {
    final maxLogit = math.max(logits[0], logits[1]);
    final legitimateExp = math.exp(logits[0] - maxLogit);
    final scamExp = math.exp(logits[1] - maxLogit);
    final total = legitimateExp + scamExp;
    final legitimateProbability = legitimateExp / total;
    final scamProbability = scamExp / total;
    final roundedScore = (scamProbability * 100).round().clamp(0, 100);
    final riskScore = roundedScore.toDouble();
    final predictedClass = scamProbability > legitimateProbability ? 1 : 0;

    return ScamPrediction(
      riskScore: riskScore,
      riskLevel: riskScore >= 70
          ? RiskLevel.high
          : riskScore >= 40
              ? RiskLevel.medium
              : RiskLevel.low,
      modelVersion: modelVersion,
      legitimateProbability: legitimateProbability,
      scamProbability: scamProbability,
      predictedClass: predictedClass,
      logits: List<double>.unmodifiable(logits),
      tokens: List<String>.unmodifiable(tokens),
      inputIds: List<int>.unmodifiable(inputIds),
      attentionMask: List<int>.unmodifiable(attentionMask),
      inputShape: List<int>.unmodifiable(inputShape),
    );
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _inferenceQueue;
    final release = Completer<void>();
    _inferenceQueue = release.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        release.complete();
      }
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    _session = null;
    _tokenizer = null;
    _initialization = null;
    if (session != null) await session.close();
  }
}

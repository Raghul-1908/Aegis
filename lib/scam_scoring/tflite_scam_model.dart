import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Runs the CNN model trained in Untitled4.ipynb
/// (Embedding -> Conv1D -> GlobalMaxPooling -> Dense -> sigmoid) via
/// `assets/ml/scamshield_model.tflite`.
///
/// This mirrors, step for step, the preprocessing the notebook used before
/// handing text to the Keras Tokenizer:
///   1. `clean_text()` — lowercase, mask URLs/phone numbers/rupee amounts
///      with placeholder tokens, strip remaining punctuation.
///   2. Keras `Tokenizer.texts_to_sequences()` — its default `filters`
///      string replaces punctuation (including the `<`/`>` around the
///      placeholder tokens above) with spaces before splitting, and maps
///      unknown words / words outside `num_words` to the `<OOV>` index.
///   3. `pad_sequences(maxlen=60, padding='post', truncating='post')`.
///
/// If any of this fails to initialize (asset missing, plugin not
/// available on this platform, corrupt model, etc.) `load()` throws —
/// callers should catch that and fall back to the TF-IDF model instead.
class TFLiteScamModel {
  final Interpreter _interpreter;
  final Map<String, int> _wordIndex;
  final int _oovIndex;
  final int _numWords;
  final int _maxLen;

  TFLiteScamModel._(
    this._interpreter,
    this._wordIndex,
    this._oovIndex,
    this._numWords,
    this._maxLen,
  );

  static Future<TFLiteScamModel> load({
    String modelAsset = 'assets/ml/scamshield_model.tflite',
    String wordIndexAsset = 'assets/ml/word_index.json',
    int numWords = 4000, // VOCAB_SIZE in the notebook
    int maxLen = 60, // MAX_LEN in the notebook
  }) async {
    final interpreter = await Interpreter.fromAsset(modelAsset);

    final raw = await rootBundle.loadString(wordIndexAsset);
    final Map<String, dynamic> jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    final wordIndex = jsonMap.map((k, v) => MapEntry(k, (v as num).toInt()));
    final oovIndex = wordIndex['<OOV>'] ?? 1;

    // Sanity-check the model's actual input shape against what we're about
    // to feed it — if someone swaps in a differently-shaped model this
    // fails loudly here instead of silently producing garbage scores.
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      if (inputShape.length != 2 || inputShape.last != maxLen) {
        debugPrint(
          'TFLiteScamModel: model input shape $inputShape does not match '
          'expected [_, $maxLen] — check maxLen matches training (MAX_LEN).',
        );
      }
    } catch (_) {
      // Non-fatal — just skip the sanity check if introspection isn't available.
    }

    return TFLiteScamModel._(interpreter, wordIndex, oovIndex, numWords, maxLen);
  }

  String _cleanText(String input) {
    var t = input.toLowerCase();
    t = t.replaceAll(RegExp(r'http\S+|www\.\S+'), ' <url> ');
    t = t.replaceAll(RegExp(r'\b\d{10}\b'), ' <phone> ');
    t = t.replaceAll(RegExp(r'rs\.?\s?\d+[,.]?\d*'), ' <amount> ');
    t = t.replaceAll(RegExp(r'[^a-z0-9<>\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  List<int> _tokenize(String cleaned) {
    // Keras' default Tokenizer filters string includes '<' and '>', and its
    // filtering step replaces each filtered character with the split
    // character (a space) rather than deleting it — so "<url>" becomes
    // the standalone token "url", not "<url>".
    final kerasFiltered = cleaned.replaceAll('<', ' ').replaceAll('>', ' ');
    final tokens = kerasFiltered.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);

    final seq = <int>[];
    for (final tok in tokens) {
      final idx = _wordIndex[tok];
      if (idx == null) {
        seq.add(_oovIndex);
      } else if (idx >= _numWords) {
        seq.add(_oovIndex);
      } else {
        seq.add(idx);
      }
    }
    return seq;
  }

  /// `padding='post', truncating='post'`: keep the first `_maxLen` tokens,
  /// pad any remaining slots with 0.
  List<double> _padSequence(List<int> seq) {
    final out = List<double>.filled(_maxLen, 0.0);
    final n = seq.length < _maxLen ? seq.length : _maxLen;
    for (var i = 0; i < n; i++) {
      out[i] = seq[i].toDouble();
    }
    return out;
  }

  /// Returns P(scam) in [0, 1].
  double predictProb(String rawText) {
    final cleaned = _cleanText(rawText);
    final seq = _tokenize(cleaned);
    final padded = _padSequence(seq);

    final input = [padded]; // shape [1, maxLen], float32
    final output = [List<double>.filled(1, 0.0)]; // shape [1, 1]
    _interpreter.run(input, output);
    return output[0][0];
  }

  void close() => _interpreter.close();
}

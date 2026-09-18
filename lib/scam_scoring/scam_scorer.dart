import 'package:flutter/foundation.dart' show debugPrint;

import 'scam_model.dart';
import 'tflite_scam_model.dart';
import 'link_checker.dart';

/// Combines both trained models into one scoring entry point:
///
/// - **Risk score**: the TFLite CNN (`assets/ml/scamshield_model.tflite`)
///   is used when it loaded successfully and inference succeeds for a
///   given message. If it failed to load at all (missing asset, plugin
///   unavailable on the platform, corrupt model) or throws on a specific
///   message, the TF-IDF + LogisticRegression model takes over — that one
///   is pure Dart with no native dependency, so it's effectively always
///   available.
/// - **Scam type** (Lottery/KYC/Digital Arrest/etc.): always comes from
///   the TF-IDF model's category classifier, since the TFLite model is
///   binary scam/legit only.
///
/// Load once (e.g. in RootShell.initState) and reuse the instance.
class ScamScorer {
  final TFLiteScamModel? _tflite;
  final ScamModel _tfidf;

  ScamScorer._(this._tflite, this._tfidf);

  /// True if the TFLite model loaded and is being used as the primary
  /// risk-scoring source. False means every score in this session is
  /// coming from the TF-IDF fallback.
  bool get usingTflite => _tflite != null;

  static Future<ScamScorer> load() async {
    // TF-IDF model is required — it also carries the category classifier.
    final tfidf = await ScamModel.instance();

    TFLiteScamModel? tflite;
    try {
      tflite = await TFLiteScamModel.load();
    } catch (e) {
      debugPrint('TFLiteScamModel unavailable, using TF-IDF for risk scoring: $e');
      tflite = null;
    }

    return ScamScorer._(tflite, tfidf);
  }

  /// Scores a notification's title + body together.
  ScamPrediction predictNotification({required String title, required String text}) {
    final combined = [title, text].where((s) => s.trim().isNotEmpty).join('. ');
    final message = combined.isEmpty ? ' ' : combined;

    // Always compute the TF-IDF prediction — cheap, pure Dart, and it's
    // the only source of the scam-type category either way.
    final tfidfPred = _tfidf.predict(message);

    if (_tflite == null) return _withLinkRisk(tfidfPred, message);

    try {
      final prob = _tflite.predictProb(message);
      final riskScore = (prob * 100).round().clamp(0, 100);
      final level = riskLevelForScore(riskScore);
      return _withLinkRisk(ScamPrediction(
        riskScore: riskScore,
        level: level,
        scamType: tfidfPred.scamType,
        categoryConfidence: tfidfPred.categoryConfidence,
      ), message);
    } catch (e) {
      debugPrint('TFLite inference failed for this message, using TF-IDF instead: $e');
      return _withLinkRisk(tfidfPred, message);
    }
  }

  ScamPrediction _withLinkRisk(ScamPrediction prediction, String message) {
    var result = prediction;
    final linkRisk = LinkChecker.check(message);
    if (linkRisk.suspicious) {
      final score = (result.riskScore + 20).clamp(0, 100);
      result = result.copyWith(
        riskScore: score,
        level: riskLevelForScore(score),
        hasSuspiciousLink: true,
        linkFindings: linkRisk.reasons,
      );
    }
    if (AdvisoryChecker.looksLikeAdvisory(message)) {
      final score = (result.riskScore - 25).clamp(0, 100);
      result = result.copyWith(
        riskScore: score,
        level: riskLevelForScore(score),
      );
    }
    return result;
  }
}

class AdvisoryChecker {
  static final RegExp _pattern = RegExp(
    r'\b(never ask|never asks|never call|never shares?|will never|do not share|don.?t share|beware of fraud|stay alert)\b',
    caseSensitive: false,
  );

  static bool looksLikeAdvisory(String text) => _pattern.hasMatch(text);
}

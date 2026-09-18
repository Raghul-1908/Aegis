import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Risk tier derived from the model's scam probability.
/// Thresholds: 0-39 safe, 40-69 medium, 70-100 high.
enum RiskLevel { safe, medium, high }

RiskLevel riskLevelForScore(int score) {
  if (score >= 70) return RiskLevel.high;
  if (score >= 40) return RiskLevel.medium;
  return RiskLevel.safe;
}

/// Friendly names for the scam-type classes the category model outputs.
/// Keys match `category_model.classes` in scam_model.json exactly.
const Map<String, String> _friendlyScamType = {
  'Legitimate': 'Legitimate',
  'Echallan': 'E-Challan Scam',
  'Lottery': 'Lottery Scam',
  'Courier': 'Courier Scam',
  'Job': 'Job Scam',
  'KYC_Suspension': 'KYC Scam',
  'Digital_Arrest': 'Digital Arrest Scam',
  'Electricity': 'Electricity Bill Scam',
  'Tax_Refund': 'Tax Refund Scam',
  'Generic': 'Scam',
  // System/device-themed scams — fake versions of routine phone notifications.
  'App_Update': 'Fake App Update Scam',
  'Storage': 'Fake Storage Alert Scam',
  'Device_Alert': 'Fake Device Alert Scam',
  'Battery': 'Fake Battery Alert Scam',
  'SIM_Network': 'Fake SIM/Network Scam',
  'WiFi': 'Fake WiFi Alert Scam',
  'Security': 'Fake Security Alert Scam',
  'Hotspot': 'Fake Hotspot Alert Scam',
  'System_Update': 'Fake System Update Scam',
  'Notification': 'Fake Notification Scam',
  'Charging': 'Fake Charging Alert Scam',
  'Bluetooth': 'Fake Bluetooth Alert Scam',
};

/// Result of scoring a single message.
class ScamPrediction {
  final int riskScore; // 0-100, probability of being a scam * 100
  final RiskLevel level;
  final String scamType; // raw class name, e.g. "Lottery" or "Legitimate"
  final double categoryConfidence; // 0-1
  final bool hasSuspiciousLink;
  final List<String> linkFindings;

  const ScamPrediction({
    required this.riskScore,
    required this.level,
    required this.scamType,
    required this.categoryConfidence,
    this.hasSuspiciousLink = false,
    this.linkFindings = const [],
  });

  ScamPrediction copyWith({int? riskScore, RiskLevel? level, bool? hasSuspiciousLink, List<String>? linkFindings}) {
    return ScamPrediction(
      riskScore: riskScore ?? this.riskScore,
      level: level ?? this.level,
      scamType: scamType,
      categoryConfidence: categoryConfidence,
      hasSuspiciousLink: hasSuspiciousLink ?? this.hasSuspiciousLink,
      linkFindings: linkFindings ?? this.linkFindings,
    );
  }

  /// Human-readable label for UI badges, e.g. "Lottery Scam" or "Safe".
  String get displayLabel {
    if (level == RiskLevel.safe) return 'Safe';
    return _friendlyScamType[scamType] ?? scamType.replaceAll('_', ' ');
  }
}

/// Loads the exported scikit-learn model (TF-IDF vectorizer weights +
/// Logistic Regression coefficients, trained offline on
/// india_fraud_detection_FINAL.csv) and runs inference entirely in Dart.
///
/// No native ML runtime (TFLite, ONNX, etc.) is required — this is a
/// linear model, so scoring is just: tokenize -> TF-IDF vector -> dot
/// product -> sigmoid/softmax. That keeps the whole thing dependency-free
/// and fast enough to run on every notification.
class ScamModel {
  final Map<String, int> _vocab;
  final List<double> _idf;
  final List<double> _riskCoef;
  final double _riskIntercept;
  final List<String> _categoryClasses;
  final List<List<double>> _categoryCoef;
  final List<double> _categoryIntercept;

  ScamModel._({
    required Map<String, int> vocab,
    required List<double> idf,
    required List<double> riskCoef,
    required double riskIntercept,
    required List<String> categoryClasses,
    required List<List<double>> categoryCoef,
    required List<double> categoryIntercept,
  })  : _vocab = vocab,
        _idf = idf,
        _riskCoef = riskCoef,
        _riskIntercept = riskIntercept,
        _categoryClasses = categoryClasses,
        _categoryCoef = categoryCoef,
        _categoryIntercept = categoryIntercept;

  static ScamModel? _cached;
  static Future<ScamModel>? _loading;

  /// Loads the model once and caches it. Safe to call from multiple
  /// places (e.g. RootShell + a settings screen) — subsequent calls
  /// reuse the same in-memory instance.
  static Future<ScamModel> instance({
    String assetPath = 'assets/ml/scam_model.json',
  }) {
    if (_cached != null) return Future.value(_cached);
    return _loading ??= _load(assetPath).then((m) {
      _cached = m;
      return m;
    });
  }

  static Future<ScamModel> _load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;

    final vocabJson = json['vocab'] as Map<String, dynamic>;
    final vocab = vocabJson.map((k, v) => MapEntry(k, v as int));

    final idf = (json['idf'] as List).map((e) => (e as num).toDouble()).toList();

    final riskModel = json['risk_model'] as Map<String, dynamic>;
    final riskCoef =
        (riskModel['coef'] as List).map((e) => (e as num).toDouble()).toList();
    final riskIntercept = (riskModel['intercept'] as num).toDouble();

    final categoryModel = json['category_model'] as Map<String, dynamic>;
    final categoryClasses =
        (categoryModel['classes'] as List).map((e) => e as String).toList();
    final categoryCoef = (categoryModel['coef'] as List)
        .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
        .toList();
    final categoryIntercept = (categoryModel['intercept'] as List)
        .map((e) => (e as num).toDouble())
        .toList();

    return ScamModel._(
      vocab: vocab,
      idf: idf,
      riskCoef: riskCoef,
      riskIntercept: riskIntercept,
      categoryClasses: categoryClasses,
      categoryCoef: categoryCoef,
      categoryIntercept: categoryIntercept,
    );
  }

  /// Same tokenizer scikit-learn's TfidfVectorizer uses by default:
  /// lowercase, then match runs of 2+ word characters.
  static final RegExp _tokenPattern = RegExp(r'\b\w\w+\b', unicode: true);

  /// Builds the sublinear-tf, IDF-weighted, L2-normalized feature vector —
  /// mirrors TfidfVectorizer(sublinear_tf=True) + default norm='l2' exactly,
  /// so scores match what scikit-learn produced during training.
  Map<int, double> _vectorize(String text) {
    final counts = <int, int>{};
    for (final m in _tokenPattern.allMatches(text.toLowerCase())) {
      final idx = _vocab[m.group(0)];
      if (idx != null) counts[idx] = (counts[idx] ?? 0) + 1;
    }

    final vec = <int, double>{};
    double sumSq = 0;
    counts.forEach((idx, c) {
      final tf = 1 + math.log(c); // sublinear_tf
      final val = tf * _idf[idx];
      vec[idx] = val;
      sumSq += val * val;
    });

    if (sumSq > 0) {
      final norm = math.sqrt(sumSq);
      vec.updateAll((_, v) => v / norm);
    }
    return vec;
  }

  double _dot(Map<int, double> vec, List<double> coef) {
    double s = 0;
    vec.forEach((idx, v) => s += v * coef[idx]);
    return s;
  }

  /// True if `_vectorize` found at least one word from the trained fraud
  /// vocabulary anywhere in the text — i.e. there's *some* lexical
  /// evidence this message is even in-domain (financial/scam-adjacent
  /// language) at all.
  bool hasVocabSignal(String text) => _vectorize(text).isNotEmpty;

  /// Scores a single message. Combine notification title + body before
  /// calling this for best accuracy (see `predictNotification`).
  ScamPrediction predict(String text) {
    final vec = _vectorize(text);

    // Binary risk model -> sigmoid probability of being a scam.
    final riskZ = _dot(vec, _riskCoef) + _riskIntercept;
    final scamProb = 1 / (1 + math.exp(-riskZ));
    final riskScore = (scamProb * 100).round().clamp(0, 100);
    final level = riskLevelForScore(riskScore);

    // Multiclass scam-type model -> softmax over classes.
    final scores = List<double>.generate(
      _categoryClasses.length,
      (i) => _dot(vec, _categoryCoef[i]) + _categoryIntercept[i],
    );
    final maxScore = scores.reduce(math.max);
    final exps = scores.map((s) => math.exp(s - maxScore)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final probs = exps.map((e) => e / sumExp).toList();

    var bestIdx = 0;
    var bestProb = -1.0;
    for (var i = 0; i < probs.length; i++) {
      if (probs[i] > bestProb) {
        bestProb = probs[i];
        bestIdx = i;
      }
    }

    return ScamPrediction(
      riskScore: riskScore,
      level: level,
      scamType: _categoryClasses[bestIdx],
      categoryConfidence: bestProb,
    );
  }

  /// Convenience wrapper: scores a notification's title + text together,
  /// the way the model was effectively trained (full message body).
  ScamPrediction predictNotification({required String title, required String text}) {
    final combined = [title, text].where((s) => s.trim().isNotEmpty).join('. ');
    return predict(combined.isEmpty ? ' ' : combined);
  }
}

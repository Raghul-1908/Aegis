enum RiskLevel { low, medium, high }

class ScamPrediction {
  const ScamPrediction({
    required this.riskScore,
    required this.riskLevel,
    required this.modelVersion,
    required this.legitimateProbability,
    required this.scamProbability,
    required this.predictedClass,
    required this.logits,
    required this.tokens,
    required this.inputIds,
    required this.attentionMask,
    required this.inputShape,
  });

  final double riskScore;
  final RiskLevel riskLevel;
  final String modelVersion;
  final double legitimateProbability;
  final double scamProbability;
  final int predictedClass;
  final List<double> logits;
  final List<String> tokens;
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> inputShape;

  bool get isScam => predictedClass == 1;
}

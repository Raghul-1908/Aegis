import 'scam_prediction.dart';

abstract class ScamModel {
  Future<void> initialize();

  Future<ScamPrediction> predict(String text);

  Future<void> dispose();
}

class ScamModelException implements Exception {
  const ScamModelException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'ScamModelException: $message'
      : 'ScamModelException: $message ($cause)';
}

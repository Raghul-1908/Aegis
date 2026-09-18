import 'package:flutter/services.dart';

import 'scam_scoring/scam_model.dart';
import 'scam_scoring/scam_scorer.dart';
import 'storage/notification_store.dart';

enum UserFeedback { scam, safe }

String _boundedText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.substring(0, text.length.clamp(0, 4000));
}

UserFeedback? _feedbackFromString(String? value) => value == 'scam'
  ? UserFeedback.scam
  : value == 'safe'
    ? UserFeedback.safe
    : null;

String? _feedbackToString(UserFeedback? value) => value?.name;

/// Bridge to the native Kotlin NotificationListenerService.
class NotificationBridge {
  static const _eventChannel = EventChannel('aegis/notifications');
  static const _methodChannel = MethodChannel('aegis/permissions');

  Stream<Map<String, dynamic>> get notificationStream {
    return _eventChannel.receiveBroadcastStream().map(
          (event) => Map<String, dynamic>.from(event as Map),
        );
  }

  Future<bool> isPermissionGranted() async {
    try {
      final granted = await _methodChannel.invokeMethod<bool>(
        'isPermissionGranted',
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _methodChannel.invokeMethod('openNotificationSettings');
    } on PlatformException {
      // Ignore — user will just need to grant manually via Settings.
    }
  }

  Future<bool> isSystemNotificationPermissionGranted() async {
    try {
      final granted = await _methodChannel.invokeMethod<bool>('isNotificationsEnabled');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }
}

/// A single captured notification, plus (once scored) the trained model's
/// risk assessment for it.
///
/// `riskScore`/`riskLevel`/`scamType` are null until the model has scored
/// the message — this normally happens synchronously right after capture
/// (see RootShell._checkPermissionAndListen), but the fields stay nullable
/// so the UI can still render something sane during the brief window
/// before the model asset finishes loading on cold start.
class CapturedNotification {
  final int? id;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final DateTime timestamp;

  final int? riskScore;
  final RiskLevel? riskLevel;
  final String? scamType;
  final bool hasSuspiciousLink;
  final List<String> linkFindings;
  final int repeatCount;
  final UserFeedback? userFeedback;

  CapturedNotification({
    this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.timestamp,
    this.riskScore,
    this.riskLevel,
    this.scamType,
    this.hasSuspiciousLink = false,
    this.linkFindings = const [],
    this.repeatCount = 1,
    this.userFeedback,
  });

  factory CapturedNotification.fromMap(Map<String, dynamic> map) {
    final rawTimestamp = map['timestamp'];
    return CapturedNotification(
        packageName: _boundedText(map['package']).isEmpty ? 'unknown' : _boundedText(map['package']),
        appName: _boundedText(map['appName']).isEmpty ? _boundedText(map['package']) : _boundedText(map['appName']),
        title: _boundedText(map['title']),
        text: _boundedText(map['text']),
      timestamp: rawTimestamp is int
          ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
          : DateTime.now(),
    );
  }

  String get contentSignature => NotificationStore.signatureFor(packageName: packageName, title: title, text: text);

  bool get isScored => riskScore != null;

  /// Returns a copy scored by the trained model (TFLite primary, TF-IDF
  /// fallback — see ScamScorer). Called once per notification, right
  /// after capture.
  CapturedNotification scoredWith(ScamScorer scorer) {
    final prediction = scorer.predictNotification(title: title, text: text);
    return copyWith(
      riskScore: prediction.riskScore,
      riskLevel: prediction.level,
      scamType: prediction.scamType,
      hasSuspiciousLink: prediction.hasSuspiciousLink,
      linkFindings: prediction.linkFindings,
    );
  }

  CapturedNotification copyWith({
    int? id,
    int? riskScore,
    RiskLevel? riskLevel,
    String? scamType,
    bool? hasSuspiciousLink,
    List<String>? linkFindings,
    int? repeatCount,
    DateTime? timestamp,
    UserFeedback? userFeedback,
    bool clearFeedback = false,
  }) {
    return CapturedNotification(
      id: id ?? this.id,
      packageName: packageName,
      appName: appName,
      title: title,
      text: text,
      timestamp: timestamp ?? this.timestamp,
      riskScore: riskScore ?? this.riskScore,
      riskLevel: riskLevel ?? this.riskLevel,
      scamType: scamType ?? this.scamType,
      hasSuspiciousLink: hasSuspiciousLink ?? this.hasSuspiciousLink,
      linkFindings: linkFindings ?? this.linkFindings,
      repeatCount: repeatCount ?? this.repeatCount,
      userFeedback: clearFeedback ? null : (userFeedback ?? this.userFeedback),
    );
  }

  Map<String, Object?> toDbMap() => {
        'package_name': packageName,
        'app_name': appName,
        'title': title,
        'text': text,
        'timestamp_ms': timestamp.millisecondsSinceEpoch,
        'risk_score': riskScore,
        'risk_level': riskLevel?.name,
        'scam_type': scamType,
        'has_suspicious_link': hasSuspiciousLink ? 1 : 0,
        'content_signature': contentSignature,
        'repeat_count': repeatCount,
        'user_feedback': _feedbackToString(userFeedback),
      };

  factory CapturedNotification.fromDbMap(Map<String, Object?> map) {
    final level = map['risk_level'] as String?;
    return CapturedNotification(
      id: map['id'] as int?,
      packageName: map['package_name'] as String? ?? 'unknown',
      appName: map['app_name'] as String? ?? 'Unknown',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp_ms'] as int? ?? 0),
      riskScore: map['risk_score'] as int?,
      riskLevel: level == null ? null : RiskLevel.values.firstWhere((item) => item.name == level, orElse: () => RiskLevel.safe),
      scamType: map['scam_type'] as String?,
      hasSuspiciousLink: (map['has_suspicious_link'] as int? ?? 0) == 1,
      repeatCount: map['repeat_count'] as int? ?? 1,
      userFeedback: _feedbackFromString(map['user_feedback'] as String?),
    );
  }
}

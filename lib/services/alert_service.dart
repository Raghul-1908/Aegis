import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:crypto/crypto.dart';

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();
  static const _channelId = 'aegis_high_risk';
  static const _methodChannel = MethodChannel('aegis/permissions');
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initialization;

  Future<void> init({bool requestPermission = false}) async {
    if (_initialized) return;
    final pending = _initialization;
    if (pending != null) return pending;
    final initialization = _initialize(requestPermission);
    _initialization = initialization;
    await initialization;
  }

  Future<bool> hasPostNotificationsPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _methodChannel.invokeMethod<bool>('isNotificationsEnabled');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _methodChannel.invokeMethod<bool>('requestNotificationPermission');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _initialize(bool shouldRequestPermission) async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: androidInit));
      if (shouldRequestPermission) {
        final granted = await AlertService.instance.requestPermission();
        debugPrint('AlertService: notification permission granted = $granted');
      }
      _initialized = true;
    } catch (error) {
      debugPrint('AlertService: initialization failed: $error');
    } finally {
      _initialization = null;
    }
  }

  int _notificationId(String appName, String preview, int riskScore) {
    final digest = sha256.convert(utf8.encode('$appName|$preview|$riskScore')).bytes;
    return 1000 + ((digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) & 0x3fffffff);
  }

  String _safePreview(String value) {
    final preview = value.trim();
    return preview.length <= 1000 ? preview : '${preview.substring(0, 997)}...';
  }

  Future<void> showHighRiskAlert({
    required String appName,
    required String preview,
    required int riskScore,
  }) async {
    final safePreview = _safePreview(preview);
    debugPrint('AlertService: attempting high risk alert for $appName ($riskScore)');
    if (!_initialized) await init(requestPermission: false);
    if (!_initialized) return;
    if (!await hasPostNotificationsPermission()) {
      debugPrint('AlertService: notification permission not granted; suppressing alert');
      return;
    }
    debugPrint('AlertService: initialized=$_initialized, showing now');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'High Risk Alerts',
        channelDescription: 'Alerts when Aegis detects a likely scam',
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFFFF3B5C),
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    try {
      await _plugin.show(
        _notificationId(appName, safePreview, riskScore),
        '\u26A0\uFE0F High risk $appName message',
        safePreview.isEmpty
            ? 'Risk score: $riskScore/100 \u2014 verify before trusting this.'
          : safePreview,
        details,
      );
      debugPrint('AlertService: show() completed without error');
    } catch (e) {
      debugPrint('AlertService: show() FAILED: $e');
    }
  }
}
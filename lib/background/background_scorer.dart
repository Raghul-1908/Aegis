import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../notification_bridge.dart';
import '../scam_scoring/scam_model.dart';
import '../scam_scoring/scam_scorer.dart';
import '../services/alert_service.dart';
import '../storage/notification_store.dart';

const _callbackChannel = MethodChannel('aegis/background_callback');
const _permissionsChannel = MethodChannel('aegis/permissions');

Future<void> registerBackgroundCallback() async {
  final handle = PluginUtilities.getCallbackHandle(_backgroundEntryPoint);
  if (handle == null) return;
  try {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _permissionsChannel.invokeMethod<void>('registerBackgroundCallback', {
          'handle': handle.toRawHandle(),
        }).timeout(const Duration(seconds: 3));
        return;
      } on Exception catch (error) {
        if (attempt == 3) {
          debugPrint('Background callback registration failed: $error');
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  } on Exception {
    // The main app can still process notifications through its EventChannel.
  }
}

@pragma('vm:entry-point')
void _backgroundEntryPoint() {
  WidgetsFlutterBinding.ensureInitialized();

  ScamScorer? scorer;
  _callbackChannel.setMethodCallHandler((call) async {
    if (call.method != 'scoreNotification') return null;

    final arguments = call.arguments;
    if (arguments is! Map) {
      await _callbackChannel.invokeMethod<void>('failed', {'jobId': ''});
      return null;
    }
    final data = Map<String, dynamic>.from(arguments);
    final jobId = data['jobId']?.toString() ?? '';
    final packageName = data['package']?.toString() ?? '';
    if (packageName == 'com.example.aegis') {
      await _callbackChannel.invokeMethod<void>('done', {'jobId': jobId});
      return null;
    }
    try {
      scorer ??= await ScamScorer.load();
      final scored = CapturedNotification.fromMap(data).scoredWith(scorer!);
      final store = NotificationStore.instance;
      final result = await store.insertOrBump(scored.toDbMap());

      if (result.inserted && scored.riskLevel == RiskLevel.high) {
        await AlertService.instance.showHighRiskAlert(
          appName: scored.appName,
          preview: scored.text.trim().isNotEmpty ? scored.text : scored.title,
          riskScore: scored.riskScore ?? 0,
        );
      }
      await _callbackChannel.invokeMethod<void>('done', {'jobId': jobId});
    } catch (error, stackTrace) {
      debugPrint('Background scoring failed: $error\n$stackTrace');
      try {
        await _callbackChannel.invokeMethod<void>('failed', {'jobId': jobId});
      } catch (_) {}
    }
    return null;
  });

  _callbackChannel.invokeMethod<void>('ready');
}
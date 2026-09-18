import 'dart:async';
import 'package:flutter/material.dart';
import 'background/background_scorer.dart';
import 'app_strings.dart';
import 'services/auth_service.dart';
import 'services/biometric_service.dart';
import 'services/prefs_service.dart';
import 'theme.dart';
import 'notification_bridge.dart';
import 'scam_scoring/scam_scorer.dart';
import 'scam_scoring/scam_model.dart';
import 'storage/notification_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'services/alert_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PrefsService.init();
  runApp(const AegisApp());
  unawaited(registerBackgroundCallback());
}

class AegisApp extends StatefulWidget {
  const AegisApp({super.key});

  @override
  State<AegisApp> createState() => _AegisAppState();
}

class _AegisAppState extends State<AegisApp> {
  AppThemeMode _themeMode = AppThemeMode.amoled;
  bool _checkingAuth = true;
  bool _authenticated = false;
  bool _accountExists = false;

  @override
  void initState() {
    super.initState();
    _themeMode = AppThemeMode.values.firstWhere(
      (mode) => mode.name == PrefsService.themeMode,
      orElse: () => AppThemeMode.amoled,
    );
    _bootstrapAuth();
  }

  Future<void> _bootstrapAuth() async {
    try {
      final exists = await AuthService.instance.hasAccount();
      var authenticated = false;
      if (exists && PrefsService.biometricUnlock && await BiometricService.instance.isSupported) {
        authenticated = await BiometricService.instance.authenticate();
      }
      if (!mounted) return;
      setState(() {
        _accountExists = exists;
        _authenticated = authenticated;
        _checkingAuth = false;
      });
    } catch (error) {
      debugPrint('Auth bootstrap failed: $error');
      if (mounted) setState(() => _checkingAuth = false);
    }
  }
                                                                            
  void _setThemeMode(AppThemeMode mode) {
    setState(() => _themeMode = mode);
    
  }

  ThemeMode get _materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.amoled:
      case AppThemeMode.blue:
        return ThemeMode.dark;
    }
  }

  AppThemeMode get _darkVariant {
    switch (_themeMode) {
      case AppThemeMode.amoled:
        return AppThemeMode.amoled;
      case AppThemeMode.blue:
        return AppThemeMode.blue;
      default:
        return AppThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(PrefsService.accentColor);
    return MaterialApp(
      title: 'Aegis',
      debugShowCheckedModeBanner: false,
      themeMode: _materialThemeMode,
      theme: buildAppTheme(AppThemeMode.light, accentOverride: accent),
      darkTheme: buildAppTheme(_darkVariant, accentOverride: accent),
      home: _checkingAuth
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_authenticated
              ? LoginScreen(accountExists: _accountExists, onAuthenticated: () => setState(() => _authenticated = true))
              : RootShell(themeMode: _themeMode, onThemeModeChanged: (mode) {
                  unawaited(PrefsService.setThemeMode(mode.name));
                  _setThemeMode(mode);
                }, onSettingsChanged: () => setState(() {})),
    );
  }
}

/// Bottom-nav shell hosting the three main tabs.
///
/// Owns notification capture, model scoring, persistence, and deduplication.
class RootShell extends StatefulWidget {
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;
  final VoidCallback onSettingsChanged;

  const RootShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onSettingsChanged,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  final NotificationBridge _bridge = NotificationBridge();
  final NotificationStore _store = NotificationStore.instance;
  final List<CapturedNotification> _notifications = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  ScamScorer? _scorer;
  bool _permissionGranted = false;
  bool _checkingPermission = true;
  TileSize _tileSize = PrefsService.tileSize;
  int _index = 0;
  List<int> _dailyCounts = List.filled(30, 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick off model loading and permission checking in parallel — both
    // are typically ready well before the first notification arrives.
    _loadModel();
    AlertService.instance.init(requestPermission: false);
    _loadHistory();
    _checkPermissionAndListen();
  }

  Future<void> _loadHistory() async {
    final rows = await _store.recent();
    final counts = await _store.dailyCounts(30);
    if (!mounted) return;
    setState(() {
      _notifications..clear()..addAll(rows.map(CapturedNotification.fromDbMap));
      _dailyCounts = counts;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissionAndListen();
  }

  Future<void> _loadModel() async {
    try {
      final scorer = await ScamScorer.load();
      if (!mounted) return;
      setState(() => _scorer = scorer);
      debugPrint(
        scorer.usingTflite
            ? 'ScamScorer: using TFLite CNN for risk scoring.'
            : 'ScamScorer: TFLite unavailable, using TF-IDF fallback for risk scoring.',
      );
    } catch (e) {
      // Both models failed — extremely unlikely (TF-IDF is pure Dart),
      // but the app still works, notifications just stay unscored.
      debugPrint('ScamScorer failed to load entirely: $e');
    }
  }

  Future<void> _checkPermissionAndListen() async {
    final granted = await _bridge.isPermissionGranted();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _checkingPermission = false;
    });

    if (granted && _sub == null) {
      _sub = _bridge.notificationStream.listen(_handleIncoming,
        onError: (e) => debugPrint('Notification stream error: $e'),
      );
    }
  }

  Future<void> _handleIncoming(Map<String, dynamic> event) async {
    final raw = CapturedNotification.fromMap(event);
    if (raw.packageName == 'com.example.aegis') return;
    if (_isNoiseNotification(raw)) return;
    final existing = await _store.findBySignature(raw.contentSignature);
    if (existing != null) {
      final id = existing['id'] as int;
      await _store.bumpRepeat(id, raw.timestamp.millisecondsSinceEpoch);
      if (!mounted) return;
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        final bumped = _notifications[index].copyWith(
          repeatCount: _notifications[index].repeatCount + 1,
          timestamp: raw.timestamp,
        );
        setState(() => _notifications..removeAt(index)..insert(0, bumped));
      }
      return;
    }
    final scored = _scorer != null ? raw.scoredWith(_scorer!) : raw;
    final result = await _store.insertOrBump(scored.toDbMap());
    final id = result.id;
    if (!result.inserted) return;
    if (!mounted) return;
    setState(() => _notifications.insert(0, scored.copyWith(id: id)));
    if (scored.riskLevel == RiskLevel.high) {
      AlertService.instance.showHighRiskAlert(
        appName: scored.appName,
        preview: scored.text.trim().isNotEmpty ? scored.text : scored.title,
        riskScore: scored.riskScore ?? 0,
      );
    }
  }

  Future<void> _requestPermission() async {
    await AlertService.instance.requestPermission();
    await _bridge.requestPermission();
  }

  Future<void> _giveFeedback(CapturedNotification notification, UserFeedback feedback) async {
    if (notification.id == null) return;
    final clear = notification.userFeedback == feedback;
    await _store.setFeedback(notification.id!, clear ? null : feedback.name);
    if (!mounted) return;
    final index = _notifications.indexWhere((item) => item.id == notification.id);
    if (index != -1) {
      setState(() => _notifications[index] = _notifications[index].copyWith(
            userFeedback: clear ? null : feedback,
            clearFeedback: clear,
          ));
    }
  }

  /// Notifications from the OS shell itself (not apps) carry no user
  /// content at all — filtering these out is safe by package name alone.
  ///
  /// NOTE: we deliberately do NOT keyword-filter on words like "charging"
  /// or "battery" anymore. The retrained model was specifically trained
  /// on real system status text vs. fake system-themed scams (e.g. "WARNING:
  /// Charging will be blocked unless you verify your account") and scores
  /// both correctly now — a keyword filter would silently hide exactly the
  /// kind of disguised scam this app exists to catch.
  static const _noisePackages = {
    'android',
    'com.android.systemui',
    'com.google.android.systemui',
    'com.android.settings',
  };

  bool _isNoiseNotification(CapturedNotification n) {
    return _noisePackages.contains(n.packageName);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final screens = [
      HomeScreen(
        notifications: _notifications,
        dailyCounts: _dailyCounts,
        permissionGranted: _permissionGranted,
        checkingPermission: _checkingPermission,
        onGrantPermission: _requestPermission,
        onViewAllNotifications: () => setState(() => _index = 1),
        visibleSections: PrefsService.homeSections,
        tileSize: _tileSize,
      ),
      NotificationsScreen(
        notifications: _notifications,
        permissionGranted: _permissionGranted,
        checkingPermission: _checkingPermission,
        onGrantPermission: _requestPermission,
        tileSize: _tileSize,
        onFeedback: _giveFeedback,
      ),
      ProfileScreen(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onSettingsChanged: () {
          setState(() {
            _tileSize = PrefsService.tileSize;
          });
          widget.onSettingsChanged();
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: AppStrings.get('home'),
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavItem(
                  icon: Icons.notifications_rounded,
                  label: AppStrings.get('notifications'),
                  selected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: AppStrings.get('profile'),
                  selected: _index == 2,
                  onTap: () => setState(() => _index = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.accentStart : colors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accentStart.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
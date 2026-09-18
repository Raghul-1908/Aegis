import 'package:shared_preferences/shared_preferences.dart';

enum TileSize { compact, comfortable, large }

extension TileSizeX on TileSize {
  String get label => switch (this) {
        TileSize.compact => 'Compact',
        TileSize.comfortable => 'Comfortable',
        TileSize.large => 'Large',
      };

  double get padding => switch (this) {
        TileSize.compact => 8,
        TileSize.comfortable => 12,
        TileSize.large => 16,
      };

  double get fontScale => switch (this) {
        TileSize.compact => 0.84,
        TileSize.comfortable => 1.0,
        TileSize.large => 1.18,
      };

  double get iconSize => switch (this) {
        TileSize.compact => 30,
        TileSize.comfortable => 38,
        TileSize.large => 46,
      };
}

enum AppLanguage { english, tamil, hindi, telugu, malayalam, kannada }

class PrefsService {
  PrefsService._();
  static SharedPreferences? _prefs;

  static const defaultSections = <String>[
    'risk_card',
    'recent_messages',
    'weekly_chart',
    'monthly_chart',
    'summary_grid',
  ];

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    final prefs = _prefs;
    if (prefs == null) throw StateError('PrefsService.init() was not called');
    return prefs;
  }

  static String get themeMode => _p.getString('theme_mode') ?? 'amoled';
  static Future<void> setThemeMode(String value) => _p.setString('theme_mode', value);

  static TileSize get tileSize => TileSize.values.firstWhere(
        (value) => value.name == _p.getString('tile_size'),
        orElse: () => TileSize.comfortable,
      );
  static Future<void> setTileSize(TileSize value) => _p.setString('tile_size', value.name);

  static List<String> get homeSections {
    final saved = _p.getStringList('home_sections');
    if (saved == null) return List<String>.from(defaultSections);
    return saved.where(defaultSections.contains).toSet().toList();
  }

  static Future<void> setHomeSections(List<String> value) => _p.setStringList(
        'home_sections',
        value.where(defaultSections.contains).toSet().toList(),
      );

  static AppLanguage get language => AppLanguage.values.firstWhere(
        (value) => value.name == _p.getString('language'),
        orElse: () => AppLanguage.english,
      );
  static Future<void> setLanguage(AppLanguage value) => _p.setString('language', value.name);

  static bool get biometricUnlock => _p.getBool('biometric_unlock') ?? true;
  static Future<void> setBiometricUnlock(bool value) => _p.setBool('biometric_unlock', value);

  static int get accentColor => _p.getInt('accent_color') ?? 0xFFFF2D78;
  static Future<void> setAccentColor(int value) => _p.setInt('accent_color', value);
}

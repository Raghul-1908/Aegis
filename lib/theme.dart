import 'package:flutter/material.dart';

enum AppThemeMode { system, light, dark, amoled, blue }

/// Custom color tokens beyond what ThemeData's ColorScheme covers.
/// Access anywhere via `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentStart;
  final Color accentEnd;
  final Color danger;
  final Color warning;
  final Color safe;

  /// Color used for the *overall* risk-status heading/icon/progress bar
  /// (e.g. "High Risk" text at the top of the risk card). Usually equals
  /// `danger`, but themes like Blue want that heading in the accent color
  /// while individual message badges keep their semantic red/orange/green.
  final Color statusAccent;

  /// Optional decorative glow gradient behind the header. Null for themes
  /// that don't use one.
  final Gradient? headerGlow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentStart,
    required this.accentEnd,
    required this.danger,
    required this.warning,
    required this.safe,
    required this.statusAccent,
    this.headerGlow,
  });

  LinearGradient get accentGradient => LinearGradient(
        colors: [accentStart, accentEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const light = AppColors(
    background: Color(0xFFF6F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0EFF5),
    border: Color(0xFFE6E5ED),
    textPrimary: Color(0xFF15141F),
    textSecondary: Color(0xFF6E6D7A),
    accentStart: Color(0xFFFF2D78),
    accentEnd: Color(0xFF7B2FF7),
    danger: Color(0xFFE8285E),
    warning: Color(0xFF8B5CF6),
    safe: Color(0xFF1FA96B),
    statusAccent: Color(0xFFE8285E),
  );

  static const dark = AppColors(
    background: Color(0xFF121218),
    surface: Color(0xFF1A1A22),
    surfaceAlt: Color(0xFF212129),
    border: Color(0xFF2A2A34),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9A99A8),
    accentStart: Color(0xFFFF2D78),
    accentEnd: Color(0xFF9B4DFF),
    danger: Color(0xFFFF3B5C),
    warning: Color(0xFFA679FF),
    safe: Color(0xFF22C55E),
    statusAccent: Color(0xFFFF3B5C),
  );

  static const amoled = AppColors(
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0D),
    surfaceAlt: Color(0xFF121216),
    border: Color(0xFF1E1E24),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF8E8D9C),
    accentStart: Color(0xFFFF2D78),
    accentEnd: Color(0xFF9B4DFF),
    danger: Color(0xFFFF3B5C),
    warning: Color(0xFFA679FF),
    safe: Color(0xFF22C55E),
    statusAccent: Color(0xFFFF3B5C),
  );

  static const blue = AppColors(
    background: Color(0xFF05070F),
    surface: Color(0xFF0B1020),
    surfaceAlt: Color(0xFF10162A),
    border: Color(0xFF1C2440),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF93A0C2),
    accentStart: Color(0xFF3B82F6),
    accentEnd: Color(0xFF60A5FA),
    danger: Color(0xFFFF4D6A),
    warning: Color(0xFFFFA43D),
    safe: Color(0xFF22C55E),
    // The blue theme's risk heading uses the accent blue, not red —
    // matches the reference where "High Risk" itself is blue while
    // individual message severity badges stay red/orange.
    statusAccent: Color(0xFF3B82F6),
    headerGlow: RadialGradient(
      center: Alignment(-0.6, -1.2),
      radius: 1.4,
      colors: [Color(0x553B82F6), Color(0x0005070F)],
    ),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accentStart,
    Color? accentEnd,
    Color? danger,
    Color? warning,
    Color? safe,
    Color? statusAccent,
    Gradient? headerGlow,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accentStart: accentStart ?? this.accentStart,
      accentEnd: accentEnd ?? this.accentEnd,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      safe: safe ?? this.safe,
      statusAccent: statusAccent ?? this.statusAccent,
      headerGlow: headerGlow ?? this.headerGlow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accentStart: Color.lerp(accentStart, other.accentStart, t)!,
      accentEnd: Color.lerp(accentEnd, other.accentEnd, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      safe: Color.lerp(safe, other.safe, t)!,
      statusAccent: Color.lerp(statusAccent, other.statusAccent, t)!,
      headerGlow: Gradient.lerp(headerGlow, other.headerGlow, t),
    );
  }
}

ThemeData buildAppTheme(AppThemeMode mode, {Color? accentOverride}) {
  final AppColors colors = switch (mode) {
    AppThemeMode.light => AppColors.light,
    AppThemeMode.dark => AppColors.dark,
    AppThemeMode.amoled => AppColors.amoled,
    AppThemeMode.blue => AppColors.blue,
    // buildAppTheme is only ever called with a concrete mode from main.dart —
    // ThemeMode.system is resolved by MaterialApp itself, not here.
    AppThemeMode.system => AppColors.dark,
  };
  final brightness = mode == AppThemeMode.light ? Brightness.light : Brightness.dark;
  final themedColors = accentOverride == null
      ? colors
      : colors.copyWith(accentStart: accentOverride, accentEnd: accentOverride);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: themedColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: themedColors.accentEnd,
      brightness: brightness,
      surface: themedColors.surface,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: themedColors.textPrimary,
      textColor: themedColors.textPrimary,
    ),
    extensions: [themedColors],
  );
}

/// Shortcut: `context.colors.textPrimary` etc.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

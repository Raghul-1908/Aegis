import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../app_strings.dart';
import '../theme.dart';
import '../storage/notification_store.dart';
import '../notification_bridge.dart';
import '../services/prefs_service.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;
  final VoidCallback? onSettingsChanged;

  const ProfileScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onSettingsChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _exporting = false;

  AppThemeMode get themeMode => widget.themeMode;
  ValueChanged<AppThemeMode> get onThemeModeChanged => widget.onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tileSize = PrefsService.tileSize;
    final language = PrefsService.language.name[0].toUpperCase() + PrefsService.language.name.substring(1);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(overscroll: false),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _ProfileHeader(colors: colors),
              const SizedBox(height: 24),
              _SectionLabel(colors: colors, label: 'Security'),
              const SizedBox(height: 8),
              _SettingsCard(
                colors: colors,
                children: [
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.notifications_active_rounded,
                    title: 'Notification Access',
                    subtitle: 'Manage permission',
                    onTap: () => NotificationBridge().requestPermission(),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.fingerprint_rounded,
                    title: 'Device authentication',
                    subtitle: PrefsService.biometricUnlock ? 'Enabled' : 'Disabled',
                    trailing: Switch.adaptive(
                      value: PrefsService.biometricUnlock,
                      activeTrackColor: colors.accentStart.withValues(alpha: 0.35),
                      activeThumbColor: colors.accentStart,
                      onChanged: (value) async {
                        await PrefsService.setBiometricUnlock(value);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(colors: colors, label: 'Appearance'),
              const SizedBox(height: 8),
              _SettingsCard(
                colors: colors,
                children: [
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.palette_rounded,
                    title: 'Theme',
                    subtitle: _themeLabel(themeMode),
                    onTap: () => _showThemeSheet(context),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.format_size_rounded,
                    title: 'Tile Size',
                    subtitle: tileSize.label,
                    onTap: () => _showTileSizeSheet(context),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.dashboard_customize_rounded,
                    title: 'Home Sections',
                    subtitle: '${PrefsService.homeSections.length} selected',
                    onTap: () => _showSectionsSheet(context),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.color_lens_rounded,
                    title: 'Accent Colour',
                    subtitle: 'Selected accent',
                    trailing: _AccentPreview(color: Color(PrefsService.accentColor), borderColor: colors.border),
                    onTap: () => _showAccentSheet(context),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.language_rounded,
                    title: AppStrings.get('language'),
                    subtitle: language,
                    onTap: () => _showLanguageSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(colors: colors, label: 'Data & Privacy'),
              const SizedBox(height: 8),
              _SettingsCard(
                colors: colors,
                children: [
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.history_rounded,
                    title: 'Notification History',
                    subtitle: 'View captured alerts',
                    onTap: null,
                    enabled: false,
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.upload_file_rounded,
                    title: 'Export Feedback for Retraining',
                    subtitle: _exporting ? 'Preparing export...' : 'Share Safe/Scam corrections as CSV',
                    onTap: _exporting ? null : () => _exportFeedback(context),
                  ),
                  _SettingsTile(
                    colors: colors,
                    icon: Icons.delete_outline_rounded,
                    title: 'Clear History',
                    subtitle: 'Remove captured notifications',
                    onTap: null,
                    enabled: false,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(colors: colors, label: 'About'),
              const SizedBox(height: 8),
              _SettingsCard(
                colors: colors,
                children: [
                  _SettingsTile(colors: colors, icon: Icons.info_outline_rounded, title: 'Aegis', subtitle: 'Privacy-focused scam detection'),
                  _SettingsTile(colors: colors, icon: Icons.verified_rounded, title: 'Version', subtitle: '1.1.0+2'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportFeedback(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await NotificationStore.instance.exportFeedbackCsv();
      if (csv.trim().split('\n').length <= 1) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No feedback yet.')));
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aegis_feedback_export.csv');
      await file.writeAsString(csv);
      final result = await Share.shareXFiles([XFile(file.path)], text: 'Aegis feedback export');
      if (result.status == ShareResultStatus.dismissed && context.mounted) {
        debugPrint('Share sheet dismissed without a target.');
      }
    } on PlatformException catch (e) {
      debugPrint('Share callback warning (usually harmless): $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export saved - please try sharing again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'System';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.amoled:
        return 'AMOLED Dark';
      case AppThemeMode.blue:
        return 'Blue';
    }
  }

  void _showThemeSheet(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Text('Choose Theme', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                ListTile(
                  onTap: () {
                    onThemeModeChanged(AppThemeMode.system);
                    Navigator.of(context).pop();
                  },
                  leading: Icon(Icons.brightness_auto_rounded, color: colors.textSecondary),
                  title: Text('System', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text('Follow your device', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  trailing: themeMode == AppThemeMode.system
                      ? Icon(Icons.check_circle_rounded, color: colors.accentStart)
                      : null,
                ),
                _ThemeOption(
                  colors: colors,
                  mode: AppThemeMode.light,
                  current: themeMode,
                  label: 'Light',
                  swatch: AppColors.light.background,
                  onSelect: onThemeModeChanged,
                ),
                _ThemeOption(
                  colors: colors,
                  mode: AppThemeMode.dark,
                  current: themeMode,
                  label: 'Dark',
                  swatch: AppColors.dark.background,
                  onSelect: onThemeModeChanged,
                ),
                _ThemeOption(
                  colors: colors,
                  mode: AppThemeMode.amoled,
                  current: themeMode,
                  label: 'AMOLED Dark',
                  swatch: AppColors.amoled.background,
                  onSelect: onThemeModeChanged,
                ),
                _ThemeOption(
                  colors: colors,
                  mode: AppThemeMode.blue,
                  current: themeMode,
                  label: 'Blue',
                  swatch: AppColors.blue.accentStart,
                  onSelect: onThemeModeChanged,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTileSizeSheet(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: TileSize.values.map((size) => ListTile(
            title: Text(size.name[0].toUpperCase() + size.name.substring(1), style: TextStyle(color: colors.textPrimary)),
            trailing: PrefsService.tileSize == size ? Icon(Icons.check_circle_rounded, color: colors.accentStart) : null,
            onTap: () async {
              await PrefsService.setTileSize(size);
              if (!mounted) return;
              setState(() {});
              widget.onSettingsChanged?.call();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showSectionsSheet(BuildContext context) {
    final colors = context.colors;
    const labels = {
      'risk_card': 'Risk score',
      'recent_messages': 'Recent messages',
      'weekly_chart': 'Weekly chart',
      'monthly_chart': 'Monthly chart',
      'summary_grid': 'Summary grid',
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selected = PrefsService.homeSections.toSet();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: PrefsService.defaultSections.map((id) => CheckboxListTile(
                value: selected.contains(id),
                title: Text(labels[id]!, style: TextStyle(color: colors.textPrimary)),
                activeColor: colors.accentStart,
                onChanged: (value) async {
                  final next = selected.toSet();
                  if (value == true) {
                    next.add(id);
                  } else if (next.length > 1) {
                    next.remove(id);
                  }
                  await PrefsService.setHomeSections(next.toList());
                  if (mounted) {
                    setState(() {});
                    widget.onSettingsChanged?.call();
                  }
                  setSheetState(() {});
                },
              )).toList(),
            ),
          );
        },
      ),
    );
  }

  void _showAccentSheet(BuildContext context) {
    final colors = context.colors;
    const accents = [
      0xFFFF2D78,
      0xFF3B82F6,
      0xFF22C55E,
      0xFFFFA43D,
      0xFF14B8A6,
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 12,
          children: accents.map((value) => InkWell(
            onTap: () async {
              await PrefsService.setAccentColor(value);
              if (!mounted) return;
              setState(() {});
              widget.onSettingsChanged?.call();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Color(value), shape: BoxShape.circle, border: Border.all(color: colors.border, width: 2)),
              child: PrefsService.accentColor == value ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLanguage.values.map((language) => ListTile(
            title: Text(language.name[0].toUpperCase() + language.name.substring(1), style: TextStyle(color: colors.textPrimary)),
            trailing: PrefsService.language == language ? Icon(Icons.check_circle_rounded, color: colors.accentStart) : null,
            onTap: () async {
              await PrefsService.setLanguage(language);
              if (!mounted) return;
              setState(() {});
              widget.onSettingsChanged?.call();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          )).toList(),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final AppColors colors;
  final AppThemeMode mode;
  final AppThemeMode current;
  final String label;
  final Color swatch;
  final ValueChanged<AppThemeMode> onSelect;

  const _ThemeOption({
    required this.colors,
    required this.mode,
    required this.current,
    required this.label,
    required this.swatch,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final selected = mode == current;
    return ListTile(
      onTap: () {
        onSelect(mode);
        Navigator.of(context).pop();
      },
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: swatch,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
      ),
      title: Text(label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
      trailing: selected ? Icon(Icons.check_circle_rounded, color: colors.accentStart) : null,
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AppColors colors;
  const _ProfileHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(gradient: colors.accentGradient, shape: BoxShape.circle),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: AuthService.instance.username,
                  builder: (context, snapshot) {
                    final username = snapshot.data ?? 'User';
                    return Text(username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final AppColors colors;
  final String label;
  const _SectionLabel({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final AppColors colors;
  final List<Widget> children;
  const _SettingsCard({required this.colors, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) Divider(color: colors.border, height: 1, indent: 52),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final AppColors colors;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final Widget? trailing;

  const _SettingsTile({
    required this.colors,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.enabled = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? colors.textPrimary : colors.textSecondary;

    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: Icon(icon, color: enabled ? colors.accentStart : colors.textSecondary, size: 20),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: colors.textSecondary, fontSize: 12)) : null,
      trailing: trailing ?? (enabled && onTap != null ? Icon(Icons.chevron_right_rounded, color: colors.textSecondary) : null),
    );
  }
}

class _AccentPreview extends StatelessWidget {
  final Color color;
  final Color borderColor;

  const _AccentPreview({required this.color, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1.5),
      ),
    );
  }
}

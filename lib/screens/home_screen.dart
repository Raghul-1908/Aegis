import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_strings.dart';
import '../theme.dart';
import '../notification_bridge.dart';
import '../scam_scoring/scam_model.dart';
import '../services/auth_service.dart';
import '../services/prefs_service.dart';

class HomeScreen extends StatelessWidget {
  final List<CapturedNotification> notifications;
  final List<int> dailyCounts;
  final bool permissionGranted;
  final bool checkingPermission;
  final VoidCallback onGrantPermission;
  final VoidCallback onViewAllNotifications;
  final List<String> visibleSections;
  final TileSize tileSize;

  const HomeScreen({
    super.key,
    required this.notifications,
    required this.dailyCounts,
    required this.permissionGranted,
    required this.checkingPermission,
    required this.onGrantPermission,
    required this.onViewAllNotifications,
    this.visibleSections = PrefsService.defaultSections,
    this.tileSize = TileSize.comfortable,
  });

  List<CapturedNotification> get _scored =>
      notifications.where((n) => n.isScored).toList();

  /// Everything below is derived live from `notifications` — no more
  /// hardcoded placeholder numbers.
  List<Map<String, dynamic>> _summaryStats() {
    final scored = _scored;
    final scams = scored.where((n) => n.riskLevel == RiskLevel.high).length;
    final medium = scored.where((n) => n.riskLevel == RiskLevel.medium).length;
    final safe = scored.where((n) => n.riskLevel == RiskLevel.safe).length;

    return [
      {'icon': Icons.forum_rounded, 'value': '${notifications.length}', 'label': 'Total\nScanned'},
      {'icon': Icons.gpp_bad_rounded, 'value': '$scams', 'label': 'Scams\nDetected'},
      {'icon': Icons.info_rounded, 'value': '$medium', 'label': 'Medium\nRisk'},
      {'icon': Icons.verified_rounded, 'value': '$safe', 'label': 'Safe\nMessages'},
    ];
  }

  /// Overall risk score for the last 24 hours, with a recent-history fallback.
  int _overallRiskScore() {
    final scored = _scored;
    if (scored.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final window = scored.where((n) => n.timestamp.isAfter(cutoff)).toList();
    final recent = window.isEmpty ? scored.take(20).toList() : window;
    return (recent.fold<int>(0, (sum, n) => sum + n.riskScore!) / recent.length).round();
  }

  int _highRiskCountLast7Days() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _scored
        .where((n) => n.riskLevel == RiskLevel.high && n.timestamp.isAfter(cutoff))
        .length;
  }

  List<CapturedNotification> _topRiskyMessages({int count = 3}) {
    final scored = _scored.where((n) => n.riskLevel != RiskLevel.safe).toList()
      ..sort((a, b) => b.riskScore!.compareTo(a.riskScore!));
    return scored.take(count).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overallScore = _overallRiskScore();
    final overallLevel = riskLevelForScore(overallScore);
    final highRiskCount = _highRiskCountLast7Days();
    final topRisky = _topRiskyMessages();

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(gradient: colors.headerGlow),
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(overscroll: false),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
            _Header(
              colors: colors,
              permissionGranted: permissionGranted,
            ),
            const SizedBox(height: 20),
            if (!checkingPermission && !permissionGranted) ...[
              _PermissionBanner(colors: colors, onGrantPermission: onGrantPermission),
              const SizedBox(height: 16),
            ],
            if (visibleSections.contains('risk_card')) _RiskScoreCard(
              colors: colors,
              score: overallScore,
              level: overallLevel,
              hasData: _scored.isNotEmpty,
              highRiskCount: highRiskCount,
            ),
            if (visibleSections.contains('risk_card')) const SizedBox(height: 16),
            if (visibleSections.contains('recent_messages')) _RecentMessagesCard(
              colors: colors,
              messages: topRisky,
              onViewAll: onViewAllNotifications,
            ),
            if (visibleSections.contains('recent_messages')) const SizedBox(height: 16),
            if (visibleSections.contains('weekly_chart') || visibleSections.contains('monthly_chart')) Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (visibleSections.contains('weekly_chart')) Expanded(child: _WeeklyChartCard(colors: colors, dailyCounts: dailyCounts)),
                if (visibleSections.contains('weekly_chart') && visibleSections.contains('monthly_chart')) const SizedBox(width: 12),
                if (visibleSections.contains('monthly_chart')) Expanded(child: _MonthlyChartCard(colors: colors, dailyCounts: dailyCounts)),
              ],
            ),
            if ((visibleSections.contains('weekly_chart') || visibleSections.contains('monthly_chart'))) const SizedBox(height: 16),
            if (visibleSections.contains('summary_grid')) _SummaryGrid(colors: colors, stats: _summaryStats(), tileSize: tileSize),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return AppStrings.get('goodMorning');
  if (hour < 17) return AppStrings.get('goodAfternoon');
  return AppStrings.get('goodEvening');
}

class _Header extends StatelessWidget {
  final AppColors colors;
  final bool permissionGranted;
  const _Header({
    required this.colors,
    required this.permissionGranted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<String?>(
          future: AuthService.instance.username,
          builder: (context, snapshot) {
            final username = snapshot.data?.trim().isNotEmpty == true ? snapshot.data!.trim() : 'User';
            return Text(
              '${_greeting()}, $username 👋',
              style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              permissionGranted ? 'Your protection is active' : 'Stay Alert. Stay Safe.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
            if (permissionGranted) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified_rounded, color: colors.accentStart, size: 14),
            ],
          ],
        ),
      ],
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final AppColors colors;
  final VoidCallback onGrantPermission;
  const _PermissionBanner({required this.colors, required this.onGrantPermission});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      colors: colors,
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: colors.accentStart, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notification access needed', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text('Grant access so Aegis can start scanning.', style: TextStyle(color: colors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          TextButton(onPressed: onGrantPermission, child: const Text('Grant')),
        ],
      ),
    );
  }
}

class _RiskScoreCard extends StatelessWidget {
  final AppColors colors;
  final int score;
  final RiskLevel level;
  final bool hasData;
  final int highRiskCount;

  const _RiskScoreCard({
    required this.colors,
    required this.score,
    required this.level,
    required this.hasData,
    required this.highRiskCount,
  });

  String get _label {
    switch (level) {
      case RiskLevel.high:
        return 'High Risk';
      case RiskLevel.medium:
        return 'Medium Risk';
      case RiskLevel.safe:
        return hasData ? 'Low Risk' : 'No Data Yet';
    }
  }

  Color get _accent {
    switch (level) {
      case RiskLevel.high:
        return colors.danger;
      case RiskLevel.medium:
        return colors.warning;
      case RiskLevel.safe:
        return colors.safe;
    }
  }

  String get _summary {
    if (!hasData) {
      return "No messages scanned yet. Aegis will score notifications as they arrive.";
    }
    if (highRiskCount == 0) {
      return "No high risk messages in the past 7 days. Keep it up.";
    }
    final plural = highRiskCount == 1 ? 'message' : 'messages';
    return "You've received $highRiskCount high risk $plural in the past 7 days. Stay cautious and verify before you trust.";
  }

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);
    final accent = _accent;

    return _CardShell(
      colors: colors,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(AppStrings.get('riskScore'), style: TextStyle(color: colors.textSecondary, fontSize: 12.5)),
                      const SizedBox(width: 4),
                      Icon(Icons.info_outline_rounded, color: colors.textSecondary, size: 13),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$score',
                        style: TextStyle(color: accent, fontSize: 34, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      Text('/100', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colors.border,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _label,
                    style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            VerticalDivider(color: colors.border, width: 1),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 1.5),
                    ),
                    child: Icon(Icons.priority_high_rounded, color: accent, size: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _label,
                    style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _summary,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentMessagesCard extends StatelessWidget {
  final AppColors colors;
  final List<CapturedNotification> messages;
  final VoidCallback onViewAll;
  const _RecentMessagesCard({required this.colors, required this.messages, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      colors: colors,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Risky Messages',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'View All',
                  style: TextStyle(color: colors.accentStart, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (messages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No risky messages detected yet.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
              ),
            )
          else ...[
            for (int i = 0; i < messages.length; i++) ...[
              _MessageRow(colors: colors, notification: messages[i]),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final AppColors colors;
  final CapturedNotification notification;
  const _MessageRow({required this.colors, required this.notification});

  @override
  Widget build(BuildContext context) {
    final bool isHigh = notification.riskLevel == RiskLevel.high;
    final Color badgeColor = isHigh ? colors.danger : colors.warning;
    final preview = notification.text.trim().isNotEmpty ? notification.text : notification.title;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 3, color: badgeColor),
            Expanded(
              child: Container(
                color: colors.surfaceAlt,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: Icon(Icons.priority_high_rounded, color: badgeColor, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: badgeColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${notification.riskScore}',
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyChartCard extends StatelessWidget {
  final AppColors colors;
  final List<int> dailyCounts;
  const _WeeklyChartCard({required this.colors, required this.dailyCounts});

  @override
  Widget build(BuildContext context) {
    final values = dailyCounts.length >= 7 ? dailyCounts.sublist(dailyCounts.length - 7) : dailyCounts;
    final previous = dailyCounts.length >= 14 ? dailyCounts.sublist(dailyCounts.length - 14, dailyCounts.length - 7) : <int>[];
    final total = values.fold<int>(0, (a, b) => a + b);
    final previousTotal = previous.fold<int>(0, (a, b) => a + b);
    final maxVal = values.isEmpty ? 1 : values.reduce(math.max).clamp(1, 999);
    final change = previousTotal == 0 ? null : ((total - previousTotal) / previousTotal * 100).round();
    final today = DateTime.now();
    final labels = List.generate(values.length, (i) {
      final day = today.subtract(Duration(days: values.length - 1 - i));
      return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];
    });

    return _CardShell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scam Messages (7 Days)', style: TextStyle(color: colors.textSecondary, fontSize: 11.5)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$total', style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
              if (change != null) ...[
                const SizedBox(width: 6),
                Icon(change >= 0 ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded, color: change >= 0 ? colors.danger : colors.safe, size: 13),
                Text('${change.abs()}%', style: TextStyle(color: change >= 0 ? colors.danger : colors.safe, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          Text(previousTotal == 0 ? 'not enough history yet' : 'vs previous 7 days', style: TextStyle(color: colors.textSecondary, fontSize: 10.5)),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 46 * (values[i] / maxVal),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: i == values.length - 1 ? colors.accentGradient : null,
                              color: i == values.length - 1 ? null : colors.border,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(labels[i], style: TextStyle(color: colors.textSecondary, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyChartCard extends StatelessWidget {
  final AppColors colors;
  final List<int> dailyCounts;
  const _MonthlyChartCard({required this.colors, required this.dailyCounts});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scam Messages (30 Days)', style: TextStyle(color: colors.textSecondary, fontSize: 11.5)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${dailyCounts.fold<int>(0, (a, b) => a + b)}', style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
          Text('total flagged this month', style: TextStyle(color: colors.textSecondary, fontSize: 10.5)),
          const SizedBox(height: 8),
          SizedBox(
            height: 66,
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(values: dailyCounts.map((e) => e.toDouble()).toList(), colors: colors),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final AppColors colors;
  _TrendPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final range = (maxVal - minVal).clamp(1, double.infinity);

    final dx = size.width / (values.length - 1);
    final points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(dx * i, size.height - ((values[i] - minVal) / range) * size.height),
    ];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [colors.accentStart.withValues(alpha: 0.35), colors.accentStart.withValues(alpha: 0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..shader = colors.accentGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}

class _SummaryGrid extends StatelessWidget {
  final AppColors colors;
  final List<Map<String, dynamic>> stats;
  final TileSize tileSize;
  const _SummaryGrid({required this.colors, required this.stats, required this.tileSize});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      colors: colors,
      child: Row(
        children: [
          for (final stat in stats)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(stat['icon'] as IconData, color: colors.accentStart, size: 22 * tileSize.fontScale),
                  const SizedBox(height: 6),
                  Text(
                    stat['value'] as String,
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16 * tileSize.fontScale),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stat['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary, fontSize: 9.5 * tileSize.fontScale, height: 1.2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final AppColors colors;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _CardShell({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

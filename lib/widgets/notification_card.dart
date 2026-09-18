import 'package:flutter/material.dart';
import '../theme.dart';
import '../notification_bridge.dart';
import '../scam_scoring/scam_model.dart';
import '../services/prefs_service.dart';

IconData appIconFor(String packageName) {
  final p = packageName.toLowerCase();
  if (p.contains('whatsapp')) return Icons.chat_bubble_rounded;
  if (p.contains('gmail') || p.contains('mail')) return Icons.email_rounded;
  if (p.contains('message') || p.contains('mms') || p.contains('sms')) {
    return Icons.sms_rounded;
  }
  if (p.contains('telegram')) return Icons.send_rounded;
  return Icons.notifications_rounded;
}

/// Displays one captured notification, including its risk badge once the
/// trained model has scored it.
///
/// `compact: true` is used for the 3-item preview on Home;
/// `compact: false` is the full row used on the Notifications tab.
class NotificationCard extends StatelessWidget {
  final CapturedNotification notification;
  final bool compact;
  final ValueChanged<UserFeedback>? onFeedback;
  final TileSize tileSize;

  const NotificationCard({
    super.key,
    required this.notification,
    this.compact = false,
    this.onFeedback,
    this.tileSize = TileSize.comfortable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = notification.title.trim().isEmpty ? notification.appName : notification.title;
    final time = '${notification.timestamp.hour.toString().padLeft(2, '0')}:'
        '${notification.timestamp.minute.toString().padLeft(2, '0')}';

    final cardPadding = tileSize.padding;
    final iconSize = compact ? tileSize.iconSize - 4 : tileSize.iconSize;
    final titleFont = switch (tileSize) {
      TileSize.compact => 12.5,
      TileSize.comfortable => 13.5,
      TileSize.large => 15.0,
    };
    final metaFont = switch (tileSize) {
      TileSize.compact => 10.5,
      TileSize.comfortable => 11.5,
      TileSize.large => 12.5,
    };
    final bodyFont = switch (tileSize) {
      TileSize.compact => 11.5,
      TileSize.comfortable => 12.5,
      TileSize.large => 13.5,
    };
    final gap = compact ? 8.0 : switch (tileSize) {
      TileSize.compact => 8.0,
      TileSize.comfortable => 10.0,
      TileSize.large => 12.0,
    };

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(gradient: colors.accentGradient, shape: BoxShape.circle),
            child: Icon(appIconFor(notification.packageName), color: Colors.white, size: compact ? 17 * tileSize.fontScale : 19 * tileSize.fontScale),
          ),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 11.5 * tileSize.fontScale, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (notification.repeatCount > 1)
                      Text('x${notification.repeatCount}', style: TextStyle(color: colors.textSecondary, fontSize: 10 * tileSize.fontScale)),
                    SizedBox(width: 8 * tileSize.fontScale),
                    Text(time, style: TextStyle(color: colors.textSecondary, fontSize: metaFont)),
                  ],
                ),
                SizedBox(height: 3 * tileSize.fontScale),
                Text(
                  title,
                  maxLines: compact ? 1 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: titleFont),
                ),
                if (notification.text.trim().isNotEmpty) ...[
                  SizedBox(height: 3 * tileSize.fontScale),
                  Text(
                    notification.text,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: bodyFont, height: 1.3),
                  ),
                ],
                if (!compact) ...[
                  SizedBox(height: 8 * tileSize.fontScale),
                  _RiskBadge(colors: colors, notification: notification),
                  if (notification.hasSuspiciousLink)
                    Text('Suspicious link', style: TextStyle(color: colors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                  if (onFeedback != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Was this scored right?', style: TextStyle(color: colors.textSecondary, fontSize: 10.5)),
                        const SizedBox(width: 8),
                        _FeedbackButton(
                          colors: colors,
                          label: 'Safe',
                          color: colors.safe,
                          selected: notification.userFeedback == UserFeedback.safe,
                          onTap: () => onFeedback!(UserFeedback.safe),
                        ),
                        const SizedBox(width: 6),
                        _FeedbackButton(
                          colors: colors,
                          label: 'Scam',
                          color: colors.danger,
                          selected: notification.userFeedback == UserFeedback.scam,
                          onTap: () => onFeedback!(UserFeedback.scam),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final AppColors colors;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.colors,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(color: selected ? color : colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) Icon(Icons.check_rounded, size: 13, color: color),
            if (selected) const SizedBox(width: 3),
            Text(label, style: TextStyle(
              color: selected ? color : colors.textSecondary,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
          ],
        ),
      ),
    );
  }
}

/// Real risk badge, driven by CapturedNotification.riskLevel/riskScore
/// (set by ScamModel right after capture in RootShell). Falls back to a
/// neutral "Analyzing…" state only for the brief window before the model
/// asset has finished loading on cold start.
class _RiskBadge extends StatelessWidget {
  final AppColors colors;
  final CapturedNotification notification;
  const _RiskBadge({required this.colors, required this.notification});

  Color _colorFor(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return colors.danger;
      case RiskLevel.medium:
        return colors.warning;
      case RiskLevel.safe:
        return colors.safe;
    }
  }

  String _labelFor(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return 'High Risk';
      case RiskLevel.medium:
        return 'Medium Risk';
      case RiskLevel.safe:
        return 'Safe';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!notification.isScored) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Analyzing…',
          style: TextStyle(fontSize: 10.5, color: colors.textSecondary, fontWeight: FontWeight.w600),
        ),
      );
    }

    final level = notification.riskLevel!;
    final color = _colorFor(level);
    final scamType = notification.scamType;
    final showType = level != RiskLevel.safe && scamType != null && scamType != 'Legitimate';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Text(
                '${_labelFor(level)} · ${notification.riskScore}',
                style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (showType)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              scamType.replaceAll('_', ' '),
              style: TextStyle(fontSize: 10, color: colors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

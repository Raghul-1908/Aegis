import 'package:flutter/material.dart';
import '../theme.dart';
import '../notification_bridge.dart';
import '../scam_scoring/scam_model.dart';
import '../widgets/notification_card.dart';
import '../services/prefs_service.dart';

enum _Filter { all, risky }

/// Full notification feed. Data and permission state are owned by
/// RootShell and passed in here — this screen just renders it.
class NotificationsScreen extends StatefulWidget {
  final List<CapturedNotification> notifications;
  final bool permissionGranted;
  final bool checkingPermission;
  final VoidCallback onGrantPermission;
  final TileSize tileSize;
  final void Function(CapturedNotification notification, UserFeedback feedback)? onFeedback;

  const NotificationsScreen({
    super.key,
    required this.notifications,
    required this.permissionGranted,
    required this.checkingPermission,
    required this.onGrantPermission,
    this.tileSize = TileSize.comfortable,
    this.onFeedback,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  _Filter _filter = _Filter.risky;

  List<CapturedNotification> get _visible => _filter == _Filter.all
      ? widget.notifications
      : widget.notifications.where((n) => !n.isScored || n.riskLevel != RiskLevel.safe).toList();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (widget.notifications.isNotEmpty)
                    Text(
                      '${widget.notifications.length} captured',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            Expanded(
                child: widget.checkingPermission
                  ? const Center(child: CircularProgressIndicator())
                  : !widget.permissionGranted
                      ? _buildPermissionPrompt(colors)
                      : widget.notifications.isEmpty
                          ? _buildEmptyState(colors)
                          : Column(children: [_buildFilterChips(colors), Expanded(child: _visible.isEmpty ? _buildEmptyState(colors) : _buildList(colors))]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ChoiceChip(label: const Text('Risky'), selected: _filter == _Filter.risky, onSelected: (_) => setState(() => _filter = _Filter.risky)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('All'), selected: _filter == _Filter.all, onSelected: (_) => setState(() => _filter = _Filter.all)),
        ],
      ),
    );
  }

  Widget _buildPermissionPrompt(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: colors.accentStart),
            const SizedBox(height: 16),
            Text(
              'Notification Access Required',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Aegis needs permission to read notifications so it can scan them for scams in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: widget.onGrantPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Grant Access'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 64, color: colors.accentStart),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Aegis is listening. New notifications will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppColors colors) {
    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(overscroll: false),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _visible.length,
        itemBuilder: (context, index) {
          final n = _visible[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 10 * widget.tileSize.fontScale),
            child: NotificationCard(
              notification: n,
              tileSize: widget.tileSize,
              onFeedback: widget.onFeedback == null ? null : (feedback) => widget.onFeedback!(n, feedback),
            ),
          );
        },
      ),
    );
  }
}

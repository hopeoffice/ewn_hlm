import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';

/// Ported from main-render.js renderNotifications() — merges global
/// broadcast + personal notifications (already merged in AppState),
/// newest first, with a bell empty-state when there are none.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Reset the badge to 0 the moment the panel opens — mirrors
    // renderNotifications() writing ewn_notif_last_seen immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().markNotificationsSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: Text(S.t('notifications', lang)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: app.notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔔', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(S.t('notifications', lang),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(S.t('notifications_sub', lang),
                      style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: app.notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final n = app.notifications[i];
                final isPersonal = n['personal'] == true || n['direct'] == true;
                final message = (n['message'] ?? '').toString();
                final dateStr = _formatDate(n);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(10)),
                        child: Text(isPersonal ? '💬' : '📢', style: const TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
                            const SizedBox(height: 6),
                            Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(Map<String, dynamic> n) {
    final ts = (n['timestamp'] as num?)?.toInt();
    final date = ts != null
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : DateTime.tryParse(n['date']?.toString() ?? '');
    if (date == null) return '';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

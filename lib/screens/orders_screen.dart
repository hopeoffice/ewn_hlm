import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../widgets/coin_icon.dart';

/// Ported from #screen-orders / .order-card / .order-status in
/// index.html + style.css.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;

    return Container(
      color: AppTheme.bg(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('📦 ${S.t('orders', lang)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.text(context))),
              ],
            ),
          ),
          Expanded(
            child: !app.isAuthenticated
                ? _EmptyState(emoji: '🔒', title: S.t('login_required', lang), sub: '')
                : app.orders.isEmpty
                    ? _EmptyState(emoji: '📦', title: S.t('no_orders', lang), sub: S.t('no_orders_sub', lang))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: app.orders.length,
                        itemBuilder: (context, i) {
                          final o = app.orders[app.orders.length - 1 - i]; // newest first
                          final status = (o['status'] ?? 'pending').toString();
                          final items = (o['items'] as List?)?.cast<Map>() ?? [];
                          final itemsSummary = items.map((it) => '${it['name']} x${it['qty']}').join('፣ ');
                          final coinsUsed = (o['coinsUsed'] as num?)?.toInt() ?? 0;
                          final coinPercent = (o['coinPercent'] as num?)?.toInt() ?? 0;
                          final isPartialCoin = coinPercent > 0 && coinPercent < 100;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.card(context),
                              borderRadius: BorderRadius.circular(AppTheme.radius),
                              border: Border.all(color: AppTheme.line(context)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('#${o['id']}',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted(context))),
                                    _StatusBadge(status: status, lang: lang),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(itemsSummary.isEmpty ? '—' : itemsSummary,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text(context))),
                                const SizedBox(height: 4),
                                Text(S.formatPrice((o['subtotal'] as num?) ?? (o['total'] as num?) ?? 0, lang),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.brand)),
                                if (coinsUsed > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(children: [
                                      const CoinIcon(size: 13),
                                      const SizedBox(width: 4),
                                      Text('${S.formatNumber(coinsUsed)} coin ${lang == 'am' ? 'ጥቅም ላይ ውሏል' : 'used'}',
                                          style: const TextStyle(fontSize: 11.5, color: AppTheme.accent)),
                                    ]),
                                  ),
                                if (o['paymentMethod'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                        isPartialCoin
                                            ? '${o['paymentMethod']} (${S.formatPrice((o['total'] as num?) ?? 0, lang)})'
                                            : '${o['paymentMethod']}',
                                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context))),
                                  ),
                                if (status == 'cancelled' && (o['cancelReason'] as String?)?.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('❌ ${o['cancelReason']}',
                                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context))),
                                  ),
                                if (o['date'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(_formatDate(o['date'].toString()),
                                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }
}

/// Ported from .order-status.pending/.delivered/.processing — now uses
/// the shared AppTheme.orderStatusColors() so this respects dark mode
/// (was previously hardcoded to the light-mode colors only).
class _StatusBadge extends StatelessWidget {
  final String status;
  final String lang;
  const _StatusBadge({required this.status, required this.lang});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = AppTheme.orderStatusColors(status, isDark: isDark);
    final label = switch (status) {
      'delivered' => lang == 'am' ? 'ደርሷል' : 'Delivered',
      'processing' => lang == 'am' ? 'በሂደት ላይ' : 'Processing',
      'cancelled' => S.t('cancelled', lang),
      _ => lang == 'am' ? 'በመጠባበቅ ላይ' : 'Pending',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  const _EmptyState({required this.emoji, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.text(context))),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 14, color: AppTheme.textMuted(context))),
          ],
        ],
      ),
    );
  }
}

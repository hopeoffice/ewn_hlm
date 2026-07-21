import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Ported from #screen-orders / .order-card / .order-status in
/// index.html + style.css.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      color: AppTheme.bgMain,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('📦 ትዕዛዞቼ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: !app.isAuthenticated
                ? const _EmptyState(emoji: '🔒', title: 'እባክዎ ይግቡ', sub: 'ትዕዛዞችዎን ለማየት መጀመሪያ መለያ ውስጥ ይግቡ')
                : app.orders.isEmpty
                    ? const _EmptyState(emoji: '📦', title: 'ምንም ትዕዛዝ የለም', sub: 'ገበያ ከጨረሱ በኋላ ትዕዛዞችዎ እዚህ ይታያሉ')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: app.orders.length,
                        itemBuilder: (context, i) {
                          final o = app.orders[app.orders.length - 1 - i]; // newest first
                          final status = (o['status'] ?? 'pending').toString();
                          final items = (o['items'] as List?)?.cast<Map>() ?? [];
                          final itemsSummary = items.map((it) => '${it['name']} x${it['qty']}').join('፣ ');

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(AppTheme.radius),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('#${o['id']}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                                    _StatusBadge(status: status),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(itemsSummary.isEmpty ? '—' : itemsSummary,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                const SizedBox(height: 4),
                                Text('${o['total'] ?? 0} ብር',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.brand)),
                                if (o['date'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(_formatDate(o['date'].toString()),
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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

/// Ported from .order-status.pending/.delivered/.processing.
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;
    switch (status) {
      case 'delivered':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'ደርሷል';
        break;
      case 'processing':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        label = 'በሂደት ላይ';
        break;
      default:
        bg = const Color(0xFFFFF3CD);
        fg = const Color(0xFF856404);
        label = 'በመጠባበቅ ላይ';
    }
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
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

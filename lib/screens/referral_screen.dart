import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../state/app_state.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';

/// Share link format matches the `?ref=CODE` query param the PWA reads
/// in index.html (`params.get('ref')`) — so a link shared from this
/// native app still works if opened in a browser, and vice versa.
class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  static const _baseUrl = 'https://ewn-hlm.web.app';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final code = app.referralCode;
    final link = code != null ? '$_baseUrl/?ref=$code' : null;
    final coinsEarned = app.referralCount * WalletService.referralCoins;
    final capReached = app.referralCount >= WalletService.maxReferralCountForCoins;

    return Scaffold(
      appBar: AppBar(title: const Text('ወዳጅዎን ያጋሩ')),
      body: code == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      const Text('🎁 ጓደኛዎን ይጋብዙ', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 10),
                      Text(
                        code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ለተመዘገበ ጓደኛ ${WalletService.referralCoins} coins ያገኛሉ',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('ኮድ ቅዳ'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('ኮድ ተቀድቷል')));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                        icon: const Icon(Icons.share, color: Colors.white, size: 18),
                        label: const Text('አጋራ', style: TextStyle(color: Colors.white)),
                        onPressed: () => Share.share(
                          '🌟 Ewn Hlm ላይ ይግቡ! የግብዣ ኮድ: $code\n$link',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _statRow('🤝 የጋበዙት ሰው ብዛት', '${app.referralCount}'),
                _statRow('🪙 ያገኙት coin', '$coinsEarned coins'),
                _statRow('🔒 ከፍተኛ ገደብ', '${WalletService.maxReferralCountForCoins} ሰው'),
                if (capReached)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'የ${WalletService.maxReferralCountForCoins}-ሰው ገደብ ላይ ደርሰዋል — ተጨማሪ ግብዣ coin አያስገኝም።',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';

/// Share link format matches the `?ref=CODE` query param the PWA reads
/// in index.html (`params.get('ref')`) — so a link shared from this
/// native app still works if opened in a browser, and vice versa.
///
/// BUGFIX: this screen used to be entirely hardcoded Amharic text with no
/// `S.t()` calls at all — switching the app to English (from Profile) had
/// no effect here. Every user-facing string now goes through `S.t()` /
/// `app.lang`, matching the rest of the app.
class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  static const _baseUrl = 'https://ewn-hlm.web.app';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final code = app.referralCode;
    final link = code != null ? '$_baseUrl/?ref=$code' : null;
    final coinsEarned = app.referralCount * WalletService.referralCoins;
    final capReached = app.referralCount >= WalletService.maxReferralCountForCoins;

    return Scaffold(
      appBar: AppBar(title: Text(S.t('refer', lang))),
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
                      Text(S.t('refer_invite', lang), style: const TextStyle(color: Colors.white70)),
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
                        S.t('refer_coins_note', lang).replaceAll('{n}', '${WalletService.referralCoins}'),
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
                        label: Text(S.t('refer_copy_code', lang)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(S.t('refer_code_copied', lang))));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                        icon: const Icon(Icons.share, color: Colors.white, size: 18),
                        label: Text(S.t('refer_share', lang), style: const TextStyle(color: Colors.white)),
                        onPressed: () => Share.share(
                          S.t('refer_share_text', lang).replaceAll('{code}', code).replaceAll('{link}', link ?? _baseUrl),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _statRow(context, S.t('refer_count_label', lang), '${app.referralCount}'),
                _statRow(context, S.t('refer_coins_earned_label', lang), '$coinsEarned coins'),
                _statRow(context, S.t('refer_cap_label', lang),
                    '${WalletService.maxReferralCountForCoins} ${S.t('refer_cap_unit', lang)}'),
                if (capReached)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      S.t('refer_cap_reached', lang).replaceAll('{n}', '${WalletService.maxReferralCountForCoins}'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: AppTheme.text(context))),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(context))),
          ],
        ),
      );
}

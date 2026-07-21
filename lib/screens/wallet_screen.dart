import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _redeeming = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final coins = app.coins;
    final etbValue = WalletService.coinsToEtb(coins);
    final canRedeem = coins >= WalletService.minRedeemCoins;

    return Scaffold(
      appBar: AppBar(title: const Text('የኔ ዋሌት')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🪙 የኮይን ቀሪ ሂሳብ', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Text('${_groupThousands(coins)} coins',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                Text('≈ ${etbValue.toStringAsFixed(2)} ብር', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _infoRow('🎁 የመመዝገቢያ ማበረታቻ', '${WalletService.signupBonusCoins} coins'),
          _infoRow('🤝 ለ 1 ሪፈር', '${WalletService.referralCoins} coins'),
          _infoRow('🔒 ከፍተኛ ሪፈር ገደብ', '${WalletService.maxReferralCountForCoins} ሰው'),
          _infoRow(
            '💵 ዝቅተኛ ማውጫ (Redeem)',
            '${WalletService.minRedeemCoins} coins (≈ ${WalletService.minRedeemEtb.toStringAsFixed(0)} ብር)',
          ),
          const SizedBox(height: 20),
          if (!canRedeem)
            Text(
              '🪙 coin ማውጣት የሚቻለው ቀሪ ሂሳብዎ ከ ${WalletService.minRedeemEtb.toStringAsFixed(0)} ብር በላይ ሲሆን ብቻ ነው።',
              style: const TextStyle(color: Colors.grey),
            ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canRedeem ? AppTheme.brand : Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (!canRedeem || _redeeming) ? null : _redeem,
            child: _redeeming
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : const Text('Coin አውጣ (Redeem)', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
        ),
      );

  Future<void> _redeem() async {
    setState(() => _redeeming = true);
    final err = await context.read<AppState>().redeemCoins();
    setState(() => _redeeming = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err == null ? '✅ ጥያቄው ተልኳል' : '⚠️ ችግር ተፈጥሯል፣ እንደገና ይሞክሩ')),
    );
  }

  // simple thousands separator (am-ET locale grouping equivalent)
  String _groupThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

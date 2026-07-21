import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_sheet.dart';
import 'wallet_screen.dart';
import 'referral_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const CircleAvatar(radius: 28, backgroundColor: AppTheme.brand, child: Icon(Icons.person, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.user?.name ?? 'እንግዳ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(app.user?.phone ?? ''),
                ],
              ),
            ),
            if (!app.isAuthenticated)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                onPressed: () => showAuthSheet(context),
                child: const Text('ግባ / ይመዝገቡ', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _tile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'የኔ ዋሌት',
          subtitle: app.isAuthenticated ? '${app.coins} coin' : 'coin፣ ቁጠባ እና ቦነስ',
          onTap: () {
            if (!app.isAuthenticated) {
              showAuthSheet(context);
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
          },
        ),
        _tile(
          icon: Icons.card_giftcard,
          title: 'ወዳጅዎን ያጋሩ፣ ያትርፉ',
          subtitle: app.isAuthenticated ? '${app.referralCount} ሰው ጋብዘዋል' : 'ጓደኛዎን ሳቡ ሽልማት ያግኙ',
          onTap: () {
            if (!app.isAuthenticated) {
              showAuthSheet(context);
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()));
          },
        ),
        _tile(icon: Icons.language, title: 'ቋንቋ', subtitle: 'ቋንቋ ይቀይሩ', onTap: () {}),
        _tile(icon: Icons.support_agent, title: 'የእርዳታ ማዕከል', subtitle: 'እርዳታ ያግኙ', onTap: () {}),
        if (app.isAuthenticated)
          _tile(
            icon: Icons.logout,
            title: 'ውጣ',
            subtitle: 'ከሂሳብዎ ይውጡ',
            onTap: () => app.logout(),
          ),
      ],
    );
  }

  Widget _tile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.brand),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

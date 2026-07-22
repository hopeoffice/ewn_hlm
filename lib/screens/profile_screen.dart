import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_sheet.dart';
import 'wallet_screen.dart';
import 'referral_screen.dart';
import 'help_center_screen.dart';

/// Ported from #screen-profile / .profile-header / .menu-list /
/// .menu-item in index.html + style.css.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      color: AppTheme.bgMain,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ---- .profile-header (gradient) ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.brand, AppTheme.brandDark],
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!app.isAuthenticated) showAuthSheet(context);
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 10),
                Text(app.user?.name ?? 'እንግዳ',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(app.user?.phone ?? '',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
                if (!app.isAuthenticated)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        side: BorderSide(color: Colors.white.withOpacity(0.5), width: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () => showAuthSheet(context),
                      child: const Text('ግባ / ይመዝገቡ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),

          // ---- .menu-list ----
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MenuItem(
                  emoji: '💰',
                  title: 'የኔ ዋሌት',
                  sub: app.isAuthenticated ? '${app.coins} coin ፣ ቁጠባ እና ቦነስ' : 'coin፣ ቁጠባ እና ቦነስ',
                  onTap: () => _requireAuth(context, app, () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()))),
                ),
                _MenuItem(
                  emoji: '🎁',
                  title: 'ወዳጅዎን ያጋሩ፣ ያትርፉ',
                  sub: app.isAuthenticated ? '${app.referralCount} ሰው ጋብዘዋል' : 'ጓደኛዎን ሳቡ ሽልማት ያግኙ',
                  onTap: () => _requireAuth(context, app, () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()))),
                ),
                _MenuItem(emoji: '🌐', title: 'ቋንቋ', sub: app.lang == 'am' ? 'አማርኛ' : 'English', onTap: () => _showLanguageSheet(context, app)),
                _MenuItem(
                  emoji: '🎧',
                  title: 'የእርዳታ ማዕከል',
                  sub: 'እርዳታ ያግኙ',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
                ),
                _ThemeToggleItem(app: app),
                if (app.isAuthenticated)
                  _MenuItem(
                    emoji: '🚪',
                    title: 'ውጣ',
                    sub: 'ከሂሳብዎ ይውጡ',
                    danger: true,
                    isLast: true,
                    onTap: () => app.logout(),
                  ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('Ewn Hlm v1.0 | እውን ህልም ©2025',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  void _requireAuth(BuildContext context, AppState app, VoidCallback action) {
    if (!app.isAuthenticated) {
      showAuthSheet(context);
      return;
    }
    action();
  }

  void _showLanguageSheet(BuildContext context, AppState app) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ቋንቋ ይምረጡ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Text('🇪🇹', style: TextStyle(fontSize: 20)),
              title: const Text('አማርኛ'),
              trailing: app.lang == 'am' ? const Icon(Icons.check, color: AppTheme.brand) : null,
              onTap: () {
                app.setLanguage('am');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text('🇬🇧', style: TextStyle(fontSize: 20)),
              title: const Text('English'),
              trailing: app.lang == 'en' ? const Icon(Icons.check, color: AppTheme.brand) : null,
              onTap: () {
                app.setLanguage('en');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Ported from the "ቀለም ገጽታ" .menu-item + .toggle-switch in index.html.
class _ThemeToggleItem extends StatelessWidget {
  final AppState app;
  const _ThemeToggleItem({required this.app});

  @override
  Widget build(BuildContext context) {
    final isDark = app.themeMode == ThemeMode.dark;
    return InkWell(
      onTap: () => app.toggleTheme(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: const Text('🌙', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ቀለም ገጽታ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  SizedBox(height: 2),
                  Text('ብርሃን / ጨለማ ቅርጸት', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Switch(
              value: isDark,
              activeColor: AppTheme.brand,
              onChanged: (_) => app.toggleTheme(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ported from .menu-item / .menu-icon / .menu-title / .menu-sub.
class _MenuItem extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool danger;
  final bool isLast;

  const _MenuItem({
    required this.emoji,
    required this.title,
    required this.sub,
    required this.onTap,
    this.danger = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger ? const Color(0xFFFFE0E0) : AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: danger ? AppTheme.danger : AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            if (!danger) const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_sheet.dart';
import 'wallet_screen.dart';
import 'referral_screen.dart';
import 'help_center_screen.dart';
import 'edit_profile_screen.dart';

/// Ported from #screen-profile / .profile-header / .menu-list /
/// .menu-item in index.html + style.css.
///
/// BUGFIX: this screen — the one place the language switcher itself lives
/// — used to be entirely hardcoded Amharic. Switching to English changed
/// every other screen but left this one (and the sub-label showing the
/// *current* language) as the only inconsistent bit. All labels now go
/// through `S.t()` / `app.lang`.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;

    return Container(
      color: AppTheme.bg(context),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ---- .profile-header (gradient) ----
          // BUGFIX: this used to be a centered Column (avatar on top, name
          // + phone below, everything center-aligned, 80px avatar). Web's
          // .profile-header is actually a left-aligned Row: a 56px avatar
          // on the left, with the name/phone stacked in a column to its
          // right — matched exactly below.
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (!app.isAuthenticated) showAuthSheet(context);
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 26),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(app.user?.name ?? S.t('guest', lang),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(app.user?.phone ?? '',
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                      ],
                    ),
                  ],
                ),
                if (!app.isAuthenticated)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          side: BorderSide(color: Colors.white.withOpacity(0.5), width: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () => showAuthSheet(context),
                        child: Text(S.t('login_btn', lang),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ---- .menu-list ----
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.line(context)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MenuItem(
                  emoji: '💰',
                  // BUGFIX: this used to reuse icon_transaction.png — the
                  // exact same icon shown for each transaction row inside
                  // the wallet screen itself — so the "My Wallet" menu
                  // entry visually blended in with transaction history.
                  // Use a dedicated wallet icon instead.
                  iconAsset: 'assets/icons/icon_wallet.png',
                  title: S.t('my_account', lang),
                  sub: app.isAuthenticated ? '${app.coins} ${S.t('my_account_sub', lang)}' : S.t('my_account_sub', lang),
                  onTap: () => _requireAuth(context, app, () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()))),
                ),
                _MenuItem(
                  emoji: '👤',
                  title: S.t('edit_profile_menu', lang),
                  sub: S.t('edit_profile_menu_sub', lang),
                  onTap: () => _requireAuth(context, app, () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()))),
                ),
                _MenuItem(
                  emoji: '🎁',
                  title: S.t('refer', lang),
                  sub: app.isAuthenticated
                      ? S.t('people_invited', lang).replaceAll('{n}', '${app.referralCount}')
                      : S.t('refer_sub', lang),
                  onTap: () => _requireAuth(context, app, () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()))),
                ),
                _MenuItem(
                  emoji: '🌐',
                  title: S.t('language', lang),
                  sub: lang == 'am' ? 'አማርኛ' : 'English',
                  onTap: () => _showLanguageSheet(context, app),
                ),
                _MenuItem(
                  emoji: '🎧',
                  iconAsset: 'assets/icons/icon_help_center.png',
                  title: S.t('help', lang),
                  sub: S.t('help_sub', lang),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
                ),
                _ThemeToggleItem(app: app),
                if (app.isAuthenticated)
                  _MenuItem(
                    emoji: '🚪',
                    title: S.t('logout', lang),
                    sub: S.t('logout_sub', lang),
                    danger: true,
                    isLast: true,
                    onTap: () => app.logout(),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                children: [
                  Text(S.t('app_footer', lang), style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(WalletService.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                    child: Text(
                      S.t('privacy_policy_menu', lang),
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context), decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
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
    final lang = app.lang;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.t('select_language', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    final lang = app.lang;
    final isDark = app.themeMode == ThemeMode.dark;
    return InkWell(
      onTap: () => app.toggleTheme(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.line(context)))),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('theme', lang), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text(context))),
                  const SizedBox(height: 2),
                  Text(S.t('theme_sub', lang), style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
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
  final String? iconAsset;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool danger;
  final bool isLast;

  const _MenuItem({
    required this.emoji,
    this.iconAsset,
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
          border: isLast ? null : Border(bottom: BorderSide(color: AppTheme.line(context))),
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
              child: iconAsset != null
                  ? Image.asset(iconAsset!, width: 20, height: 20)
                  : Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: danger ? AppTheme.danger : AppTheme.text(context))),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
                ],
              ),
            ),
            if (!danger) Icon(Icons.chevron_right, color: AppTheme.textMuted(context), size: 18),
          ],
        ),
      ),
    );
  }
}

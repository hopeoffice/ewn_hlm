import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../services/update_service.dart';
import '../screens/home_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/profile_screen.dart';

/// Ported from #bottom-nav / .nav-item in index.html + style.css.
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});
  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> with WidgetsBindingObserver {
  int _index = 0;

  // ---- App update check (Task: Stage 5 — force/soft update) ----
  // Ported from checkForAppUpdate()'s polling strategy in main-actions.js:
  // once at startup, every 60s while the app is open, and again whenever
  // the app regains focus/foreground.
  Timer? _updateTimer;
  AppUpdateInfo? _softUpdate;
  bool _softUpdateDismissed = false;
  bool _mandatoryDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdate();
    _updateTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_mandatoryDialogShowing) return;
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    if (info.mandatory) {
      _showMandatoryUpdateDialog(info);
    } else if (!_softUpdateDismissed) {
      setState(() => _softUpdate = info);
    }
  }

  void _showMandatoryUpdateDialog(AppUpdateInfo info) {
    _mandatoryDialogShowing = true;
    final lang = context.read<AppState>().lang;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(S.t('update_required_title', lang)),
          content: Text(lang == 'am' ? info.messageAm : info.messageEn),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
              onPressed: () => _openStore(info.storeUrl),
              child: Text(S.t('update_now', lang), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStore(String? storeUrl) async {
    if (storeUrl == null) return;
    final uri = Uri.tryParse(storeUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  final _screens = const [HomeScreen(), CartScreen(), OrdersScreen(), ProfileScreen()];

  static const _tabs = [
    (icon: 'assets/icons/nav_home.png', key: 'home'),
    (icon: 'assets/icons/nav_cart.png', key: 'cart'),
    (icon: 'assets/icons/nav_orders.png', key: 'orders'),
    (icon: 'assets/icons/nav_profile.png', key: 'profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cartCount = app.cartCount;

    return Scaffold(
      backgroundColor: AppTheme.brand,
      // top:false — the home header (brand-colored) bleeds edge-to-edge
      // behind the status bar, like the PWA's fixed header.
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            _screens[_index],
            // Ported from #soft-update-banner in index.html — dismissible,
            // shown when an update exists but isn't mandatory.
            if (_softUpdate != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  color: AppTheme.card(context),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Text('⬆️', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.t('soft_update_title', app.lang),
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.text(context))),
                              Text(
                                app.lang == 'am' ? _softUpdate!.messageAm : _softUpdate!.messageEn,
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _softUpdateDismissed = true;
                            _softUpdate = null;
                          }),
                          child: Text(S.t('soft_update_later', app.lang)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                          onPressed: () => _openStore(_softUpdate!.storeUrl),
                          child: Text(S.t('update_now', app.lang), style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -4))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_tabs.length, (i) {
              final active = i == _index;
              final tab = _tabs[i];
              return GestureDetector(
                onTap: () => setState(() => _index = i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Opacity(
                            opacity: active ? 1.0 : 0.55,
                            child: Image.asset(tab.icon, width: active ? 26 : 23, height: active ? 26 : 23),
                          ),
                          if (i == 1 && cartCount > 0)
                            Positioned(
                              top: -4,
                              right: -8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(10)),
                                child: Text('$cartCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(S.t(tab.key, app.lang),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: active ? AppTheme.brand : AppTheme.textMuted(context))),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

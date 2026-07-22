import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
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

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  final _screens = const [HomeScreen(), CartScreen(), OrdersScreen(), ProfileScreen()];

  static const _tabs = [
    (emoji: '🏠', key: 'home'),
    (emoji: '🛒', key: 'cart'),
    (emoji: '📦', key: 'orders'),
    (emoji: '👤', key: 'profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cartCount = app.cartCount;

    return Scaffold(
      backgroundColor: AppTheme.brand,
      // top:false — the home header (brand-colored) bleeds edge-to-edge
      // behind the status bar, like the PWA's fixed header.
      body: SafeArea(top: false, child: _screens[_index]),
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
                          Text(tab.emoji, style: TextStyle(fontSize: active ? 24 : 22)),
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
                              color: active ? AppTheme.brand : AppTheme.textSecondary)),
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

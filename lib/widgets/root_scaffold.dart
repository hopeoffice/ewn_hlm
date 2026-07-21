import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../screens/home_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/profile_screen.dart';

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});
  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  final _screens = const [HomeScreen(), CartScreen(), OrdersScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<AppState>().cartCount;

    return Scaffold(
      body: SafeArea(child: _screens[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'መነሻ'),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('$cartCount'),
              isLabelVisible: cartCount > 0,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            label: 'ጋሪ',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'ትዕዛዞች'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'መገለጫ'),
        ],
      ),
    );
  }
}

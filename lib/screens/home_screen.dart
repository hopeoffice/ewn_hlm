import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.offline && app.products.isEmpty) {
      return const _OfflineView();
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppTheme.brand,
          title: const Text('🌟 Ewn Hlm'),
          actions: [
            IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ፈልግ...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onChanged: app.setSearch,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final p = app.filteredProducts[i];
                return ProductCard(product: p, onTap: () {});
              },
              childCount: app.filteredProducts.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('ከመስመር ውጭ ነዎት', style: TextStyle(fontSize: 16)),
          const Text('የኢንተርኔት ግንኙነትዎን ያረጋግጡ'),
        ],
      ),
    );
  }
}

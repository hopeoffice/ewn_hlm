import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/category_chip.dart';
import '../widgets/banner_carousel.dart';

/// Ported from #screen-home in index.html — header, search bar, ad
/// carousel, category chips, discount section, then the products grid.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.offline && app.products.isEmpty) {
      return const _OfflineView();
    }

    return Container(
      color: AppTheme.bgMain,
      child: CustomScrollView(
        slivers: [
          // ---- Header (.app-header) ----
          SliverToBoxAdapter(
            child: Container(
              color: AppTheme.brand,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                children: [
                  const Text('📍', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('አካባቢ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        Text('አካባቢዎን እያገኘን...',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Text('❤️', style: TextStyle(fontSize: 18)),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Text('🔔', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),

          // ---- Search bar, floating over the header/body seam ----
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'ምርቶችን ይፈልጉ...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                          onChanged: app.setSearch,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ---- Ad banner carousel ----
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -8),
              child: BannerCarousel(
                onSearchTap: () {},
                onCategoryTap: app.setCategory,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ---- Categories (.section-header + .categories-scroll) ----
          const SliverToBoxAdapter(child: _SectionHeader(title: 'ምድቦች')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: app.categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final c = app.categories[i];
                  return CategoryChip(
                    category: c,
                    active: app.activeCategory == c.id,
                    onTap: () => app.setCategory(c.id),
                  );
                },
              ),
            ),
          ),

          // ---- Discount section (#discount-section) ----
          if (app.discountedProducts.isNotEmpty) ...[
            const SliverToBoxAdapter(child: _SectionHeader(title: '🔥 ዋጋ ቅናሽ')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: app.discountedProducts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final p = app.discountedProducts[i];
                    return SizedBox(width: 150, child: ProductCard(product: p, onTap: () {}));
                  },
                ),
              ),
            ),
          ],

          // ---- Products grid (.products-grid) ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ምርቶች', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  TextButton(onPressed: () {}, child: const Text('ሁሉንም ይዩ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
          if (app.filteredProducts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('ምንም ምርት አልተገኘም', style: TextStyle(color: AppTheme.textSecondary))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
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

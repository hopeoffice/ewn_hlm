import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/product.dart';
import '../l10n/strings.dart';
import '../widgets/product_card.dart';
import '../widgets/category_chip.dart';
import '../widgets/banner_carousel.dart';
import 'likes_screen.dart';
import 'notifications_screen.dart';
import 'product_detail_sheet.dart';

/// Ported from #screen-home in index.html — header, search bar, ad
/// carousel, category chips, discount section, then the products grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
                      children: [
                        Text(S.t('location', app.lang), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        Text(
                          app.locationName ?? S.t('getting_location', app.lang),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _HeaderIconBtn(
                    emoji: '❤️',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LikesScreen())),
                  ),
                  const SizedBox(width: 10),
                  _HeaderIconBtn(
                    emoji: '🔔',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    badgeCount: app.unreadNotifCount,
                  ),
                ],
              ),
            ),
          ),

          // ---- Location permission banner (Task #13) ----
          if (app.showLocationBanner)
            SliverToBoxAdapter(child: _LocationBanner(app: app)),

          // ---- Search bar, floating over the header/body seam ----
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      const Text('🔍', style: TextStyle(fontSize: 16, color: Color(0xFF999999))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: S.t('search', app.lang),
                            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
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
          SliverToBoxAdapter(child: _SectionHeader(title: S.t('categories', app.lang))),
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
                    lang: app.lang,
                  );
                },
              ),
            ),
          ),

          // ---- Discount section (#discount-section / renderDiscountSection()) ----
          // NOTE: this is a dedicated horizontal-scroll card layout on the
          // web app — NOT the same card as the products grid. It shows a
          // "-XX%" badge computed with a specific non-linear scale (see
          // _DiscountCard below), not the plain "ቅናሽ" tag used elsewhere.
          if (app.discountedProducts.isNotEmpty) ...[
            SliverToBoxAdapter(child: _SectionHeader(title: app.lang == 'am' ? 'ዋጋ ቅናሽ' : 'Special Offers')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  itemCount: app.discountedProducts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = app.discountedProducts[i];
                    return _DiscountCard(product: p, lang: app.lang, onTap: () => showProductDetail(context, p));
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
          ],

          // ---- Products grid (.products-grid) ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(S.t('products_section', app.lang),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  // Matches the web's <button ... onclick=""> — present
                  // but intentionally inert; the web app never wired it up.
                  TextButton(
                    onPressed: () {},
                    child: Text(S.t('see_all', app.lang),
                        style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          if (app.filteredProducts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text(S.t('no_products', app.lang), style: const TextStyle(color: AppTheme.textSecondary))),
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
                    return ProductCard(product: p, onTap: () => showProductDetail(context, p));
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

/// Ported from .icon-btn/.badge in style.css — 38×38 translucent circle,
/// gold notification badge (was previously plain IconButtons with a
/// red badge, neither of which matched the CSS).
class _HeaderIconBtn extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  final int badgeCount;
  const _HeaderIconBtn({required this.emoji, required this.onTap, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.gold, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ported from #location-permission-banner in index.html/style.css.
class _LocationBanner extends StatelessWidget {
  final AppState app;
  const _LocationBanner({required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          const Text('📍', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('location_banner_title', app.lang),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                Text(S.t('location_banner_sub', app.lang),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          TextButton(onPressed: app.dismissLocationBanner, child: Text(S.t('later', app.lang))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, minimumSize: const Size(0, 34)),
            onPressed: app.requestLocation,
            child: Text(S.t('allow', app.lang), style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Ported from .disc-card / renderDiscountSection() in main-ui.js. A wide
/// landscape card (image left, info right) with a percentage-off badge —
/// distinct from the plain "ቅናሽ" tag used on the products grid.
class _DiscountCard extends StatelessWidget {
  final Product product;
  final String lang;
  final VoidCallback onTap;
  const _DiscountCard({required this.product, required this.lang, required this.onTap});

  /// Ported verbatim from renderDiscountSection(): rawPct is the true
  /// percentage off, but the *displayed* badge scales it ×10 (capped at
  /// 60%) — e.g. a real 6% discount shows as "-60%". This is an
  /// intentional (if unusual) admin-configured display rule on the web
  /// app, not a bug — kept exactly as-is so the numbers match.
  int get _badgePercent {
    final oldPrice = product.price;
    final newPrice = product.discountedPrice ?? product.price;
    final rawPct = ((oldPrice - newPrice) / oldPrice * 100).round();
    return rawPct == 0 ? 5 : (rawPct * 10).clamp(0, 60);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        height: 130,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B4332), Color(0xFF2D6A4F), Color(0xFF40916C)],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              height: 130,
              child: product.thumbnail.isNotEmpty
                  ? Image.network(product.thumbnail, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _NoImg())
                  : const _NoImg(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFF4A261), borderRadius: BorderRadius.circular(6)),
                      child: Text('-$_badgePercent%',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      product.displayName(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${S.formatNumber(product.price)} ETB',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.65), fontSize: 10.5, decoration: TextDecoration.lineThrough)),
                        Text('${S.formatNumber(product.discountedPrice ?? product.price)} ETB',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoImg extends StatelessWidget {
  const _NoImg();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white.withOpacity(0.1),
        alignment: Alignment.center,
        child: const Text('📦', style: TextStyle(fontSize: 28)),
      );
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
    final lang = context.watch<AppState>().lang;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(lang == 'am' ? 'ከመስመር ውጭ ነዎት' : 'You are offline', style: const TextStyle(fontSize: 16)),
          Text(lang == 'am' ? 'የኢንተርኔት ግንኙነትዎን ያረጋግጡ' : 'Please check your internet connection'),
        ],
      ),
    );
  }
}

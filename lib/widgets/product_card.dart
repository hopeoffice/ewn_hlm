import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';

/// Ported from .product-card / .product-img-wrap / .stock-badge /
/// .like-btn / .product-price in style.css.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final liked = app.likes.contains(product.id);
    final hasDiscount = product.discountedPrice != null && product.discountedPrice! < product.price;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              // .product-img-wrap { padding-top: 85% }
              aspectRatio: 1 / 0.85,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppTheme.brand,
                    alignment: Alignment.center,
                    child: const Text('በመጫን ላይ...',
                        style: TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center),
                  ),
                  if (product.thumbnail.isNotEmpty)
                    Image.network(
                      product.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  // .stock-badge.sale — top-left, only when discounted
                  if (hasDiscount)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Badge(text: S.t('discounted', app.lang), bg: AppTheme.accent, fg: Colors.white),
                    ),
                  // .stock-badge.out — bottom-left, out-of-stock
                  if (product.outOfStock)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: _Badge(text: S.t('out_of_stock', app.lang), bg: const Color(0xFFFFE0E0), fg: const Color(0xFFC62828)),
                    ),
                  // .like-btn — top-right circular button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => app.toggleLike(product.id),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: liked ? const Color(0xFFFFE0E0) : Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(liked ? Icons.favorite : Icons.favorite_border,
                            color: liked ? AppTheme.danger : AppTheme.textSecondary, size: 15),
                      ),
                    ),
                  ),
                  if (product.outOfStock)
                    Container(color: Colors.black.withOpacity(0.25)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.displayName(app.lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, height: 1.4),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(S.formatPrice(product.displayPrice, app.lang),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.brand)),
                          if (hasDiscount)
                            Text(S.formatPrice(product.price, app.lang),
                                style: const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: AppTheme.textSecondary,
                                    fontSize: 11)),
                        ],
                      ),
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

class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Badge({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

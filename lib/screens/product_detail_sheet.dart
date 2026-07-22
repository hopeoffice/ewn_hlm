import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../widgets/auth_sheet.dart';
import 'checkout_screen.dart';

/// Ported from openProduct() / .modal-sheet in index.html + main-actions.js:
/// image carousel, name, price + qty selector, bullet-point description,
/// color swatches, then "Add to Cart" / "Buy Now" buttons.
Future<void> showProductDetail(BuildContext context, Product product) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProductDetailSheet(product: product),
  );
}

class _ProductDetailSheet extends StatefulWidget {
  final Product product;
  const _ProductDetailSheet({required this.product});

  @override
  State<_ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<_ProductDetailSheet> {
  int _qty = 1;
  String? _selectedColor;
  int _carouselIndex = 0;
  late final PageController _pageCtrl = PageController();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = widget.product;
    final liked = app.likes.contains(p.id);
    final hasDiscount = p.discountedPrice != null && p.discountedPrice! < p.price;
    final images = p.images.isNotEmpty ? p.images : [''];
    final bullets = p.displayBullets(app.lang);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(
                    height: 260,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _pageCtrl,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _carouselIndex = i),
                          itemBuilder: (context, i) => images[i].isNotEmpty
                              ? Image.network(images[i], fit: BoxFit.cover, width: double.infinity)
                              : Container(color: AppTheme.brand),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 10,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (i) {
                                final active = i == _carouselIndex;
                                return Container(
                                  width: active ? 18 : 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: active ? Colors.white : Colors.white54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.displayName(app.lang),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        const SizedBox(height: 12),

                        // ---- Price + qty selector, side by side (Task #6) ----
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(S.formatPrice(p.displayPrice, app.lang),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.brand)),
                                if (hasDiscount) ...[
                                  const SizedBox(width: 8),
                                  Text(S.formatPrice(p.price, app.lang),
                                      style: const TextStyle(
                                          decoration: TextDecoration.lineThrough,
                                          color: AppTheme.textSecondary,
                                          fontSize: 13)),
                                ],
                              ],
                            ),
                            if (!p.outOfStock)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppTheme.border),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                                      icon: const Icon(Icons.remove, size: 18),
                                    ),
                                    Text('$_qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      onPressed: () => setState(() => _qty++),
                                      icon: const Icon(Icons.add, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (p.outOfStock)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xFFFFE0E0), borderRadius: BorderRadius.circular(8)),
                              child: Text(S.t('out_of_stock', app.lang),
                                  style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),

                        // ---- Description bullets (Task #17) — was entirely
                        // missing before; ported from the descHTML block in
                        // openProduct() (main-actions.js). ----
                        if (bullets.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ...bullets.map((line) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('●', style: TextStyle(color: AppTheme.gold, fontSize: 10, height: 1.6)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(line,
                                          style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary, height: 1.5)),
                                    ),
                                  ],
                                ),
                              )),
                        ],

                        // ---- Colors — real swatch circles (not text chips),
                        // ported from buildColorsHTML() (main-render.js).
                        // `p.colors` are hex codes, e.g. "#0d5c42". ----
                        if (p.colors.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(S.t('color_optional', app.lang),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              if (_selectedColor != null)
                                Text(S.t('color_selected', app.lang),
                                    style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: p.colors.map((hex) {
                              final color = _parseHexColor(hex);
                              final active = _selectedColor == hex;
                              final light = color != null && _isLightColor(color);
                              return GestureDetector(
                                onTap: () => setState(() => _selectedColor = active ? null : hex),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: color ?? AppTheme.border,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: active
                                          ? AppTheme.brand
                                          : (light ? AppTheme.border : Colors.transparent),
                                      width: active ? 3 : 1,
                                    ),
                                    boxShadow: active
                                        ? [BoxShadow(color: AppTheme.brand.withOpacity(0.3), blurRadius: 6)]
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: AppTheme.brand),
                                ),
                                onPressed: p.outOfStock
                                    ? null
                                    : () {
                                        context.read<AppState>().addToCart(p, color: _selectedColor, qty: _qty);
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(content: Text('🛒 ወደ ጋሪ ተጨምሯል')));
                                      },
                                child: Text(S.t('add_to_cart', app.lang),
                                    style: const TextStyle(color: AppTheme.brand, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brand,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: p.outOfStock ? null : () => _buyNow(context, app, p),
                                child: Text(S.t('buy_now', app.lang),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _RoundIconButton(icon: Icons.close, onTap: () => Navigator.of(context).pop()),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _RoundIconButton(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  iconColor: liked ? AppTheme.danger : AppTheme.textSecondary,
                  onTap: () => app.toggleLike(p.id),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Ported from quickOrder() in main-actions.js — requires auth, SETS
  /// (not adds to) the cart line's qty/color, then opens checkout for
  /// just that item.
  void _buyNow(BuildContext context, AppState app, Product p) {
    if (!app.isAuthenticated) {
      Navigator.of(context).pop();
      showAuthSheet(context);
      return;
    }
    app.setCartQty(p, color: _selectedColor, qty: _qty);
    final idx = app.cart.indexWhere((c) => c.id == p.id && c.color == _selectedColor);
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CheckoutScreen(cartIndex: idx >= 0 ? idx : null)),
    );
  }
}

/// Ported from isLightColor() in main-render.js — perceived-brightness
/// formula, used to decide whether a swatch needs a visible border.
bool _isLightColor(Color c) {
  final brightness = (c.red * 299 + c.green * 587 + c.blue * 114) / 1000;
  return brightness > 180;
}

Color? _parseHexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: iconColor ?? AppTheme.textPrimary),
      ),
    );
  }
}

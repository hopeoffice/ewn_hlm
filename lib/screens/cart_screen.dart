import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import 'checkout_screen.dart';

/// Ported from #screen-cart / .cart-item / .qty-btn / .cart-item-buy-btn
/// in index.html + style.css + renderCart() (main-render.js).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;

    return Container(
      color: AppTheme.bgMain,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                // NOTE: the web markup literally has "🛒 ጋሪ" in the HTML,
                // but applyI18nToPage() replaces textContent with t('cart')
                // on load — which has NO emoji — so the real rendered
                // title is just "ጋሪ"/"Cart".
                Text(S.t('cart', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: app.cart.isEmpty
                ? _EmptyState(
                    emoji: '🛒',
                    title: S.t('cart_empty', lang),
                    sub: S.t('cart_empty_sub', lang),
                    ctaLabel: S.t('shop_now', lang),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: app.cart.length,
                    itemBuilder: (context, i) {
                      final item = app.cart[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          border: Border.all(color: AppTheme.border),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                              child: item.image.isNotEmpty
                                  ? Image.network(item.image, width: 70, height: 70, fit: BoxFit.cover)
                                  : Container(width: 70, height: 70, color: AppTheme.brand),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(S.formatPrice(item.price, lang),
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.brand)),
                                      // Color swatch — a small circle, same
                                      // as .cart-item-color-swatch — not raw
                                      // hex text.
                                      if (item.color != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: _parseHexColor(item.color!) ?? AppTheme.border,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppTheme.border),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _QtyBtn(
                                          icon: Icons.remove,
                                          onTap: () => app.updateQty(item.id, item.color, item.qty - 1)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      ),
                                      _QtyBtn(
                                          icon: Icons.add,
                                          onTap: () => app.updateQty(item.id, item.color, item.qty + 1)),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () => app.removeFromCart(item.id, item.color),
                                        child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.brand,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _goToCheckout(context, app, i),
                                      child: Text('${S.t('buy_item', lang)} →',
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (app.cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${S.t('cart_total', lang)}: ${S.formatPrice(app.cartTotal, lang)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () => _goToCheckout(context, app, null),
                    child: Text(S.t('checkout', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _goToCheckout(BuildContext context, AppState app, int? cartIndex) {
    if (!app.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ትዕዛዝ ለመላክ እባክዎ ይግቡ')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutScreen(cartIndex: cartIndex)));
  }
}

Color? _parseHexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppTheme.bgMain,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(icon, size: 14, color: AppTheme.textPrimary),
      ),
    );
  }
}

/// Ported from .empty-state / .empty-emoji / .empty-title / .empty-sub +
/// the "Shop Now" CTA button (present on web, was missing here before).
class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  final String ctaLabel;
  const _EmptyState({required this.emoji, required this.title, required this.sub, required this.ctaLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            // navigate('home') on the web — here, just popping back to the
            // Home tab is the closest equivalent since Cart lives inside
            // the same bottom-nav shell.
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(ctaLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: product.thumbnail.isNotEmpty
                      ? Image.network(product.thumbnail, fit: BoxFit.cover)
                      : Container(color: AppTheme.brand.withOpacity(0.1)),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => app.toggleLike(product.id),
                    child: Icon(liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? Colors.red : Colors.white, size: 22),
                  ),
                ),
                if (product.outOfStock)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: const Text('ተሽጦ አልቋል',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${product.displayPrice.toStringAsFixed(0)} ብር',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.brand)),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text('${product.price.toStringAsFixed(0)} ብር',
                            style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                                fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

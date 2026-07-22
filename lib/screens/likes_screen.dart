import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../widgets/product_card.dart';
import 'product_detail_sheet.dart';

/// Ported from #screen-likes / renderLikes() in main-render.js — same
/// products-grid as Home, filtered to state.likes.
class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final liked = app.products.where((p) => app.likes.contains(p.id)).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(
        title: Text(S.t('my_likes', lang)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: liked.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🤍', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(S.t('no_likes', lang), style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemCount: liked.length,
              itemBuilder: (context, i) {
                final p = liked[i];
                return ProductCard(product: p, onTap: () => showProductDetail(context, p));
              },
            ),
    );
  }
}

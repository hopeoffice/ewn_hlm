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
      backgroundColor: AppTheme.bg(context),
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
                  // BUGFIX: the '🤍' emoji glyph doesn't render on every
                  // device/font (shows blank on some phones). A Material
                  // icon renders identically everywhere.
                  Icon(Icons.favorite_border, size: 48, color: AppTheme.textMuted(context)),
                  const SizedBox(height: 12),
                  Text(S.t('no_likes', lang), style: TextStyle(color: AppTheme.textMuted(context))),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.56,
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

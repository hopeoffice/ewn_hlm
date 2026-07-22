// Ported 1:1 from `normalizeProduct()` in main-config.js so that the
// existing Firestore `products` collection needs NO changes.
class Product {
  final String id;

  // ---- Name ----
  // Firestore schema is `name` (base — required, shown by default) +
  // optional `nameAm` (Amharic override). NOTE: this is the OPPOSITE of
  // what an earlier version of this model assumed (it treated `name` as
  // always-Amharic and looked for a nonexistent `name_en` field, so the
  // language toggle never actually changed a product's displayed name).
  final String name;
  final String? nameAm;

  // ---- Description ----
  // Two representations, same fallback chain as openProduct()/
  // renderProducts() in main-actions.js/main-render.js:
  //   1) Bullet points (descBullets / descBulletsAm) — preferred, shown as
  //      a list with a yellow dot marker.
  //   2) Plain description (description / descriptionAm) — used only when
  //      no bullets exist; split on '\n' as a bullets fallback too.
  final List<String> descBullets;
  final List<String> descBulletsAm;
  final String? description;
  final String? descriptionAm;

  final double price;
  final double? discountedPrice;
  final String category;
  final List<String> images;
  final List<String> colors;
  final bool hidden;
  final bool outOfStock;

  Product({
    required this.id,
    required this.name,
    this.nameAm,
    this.descBullets = const [],
    this.descBulletsAm = const [],
    this.description,
    this.descriptionAm,
    required this.price,
    this.discountedPrice,
    required this.category,
    required this.images,
    required this.colors,
    required this.hidden,
    required this.outOfStock,
  });

  /// Legacy category migration — same map as CATEGORY_MIGRATION in JS.
  static const Map<String, String> _categoryMigration = {
    'electronics': 'phones',
    'fashion': 'kitchen',
    'home': 'laptops',
    'food': 'kitchen',
    'beauty': 'beauty_health',
  };

  factory Product.fromMap(String id, Map<String, dynamic> p) {
    final rawImages = (p['images'] as List?)?.cast<String>() ?? [];
    final singleImage = p['image'] as String?;
    final images = rawImages.isNotEmpty
        ? rawImages
        : (singleImage != null && singleImage.isNotEmpty ? [singleImage] : <String>[]);

    final rawCategory = p['category'] as String? ?? '';
    final category = _categoryMigration[rawCategory] ?? rawCategory;

    return Product(
      id: id,
      name: p['name'] as String? ?? '',
      nameAm: p['nameAm'] as String?,
      descBullets: (p['descBullets'] as List?)?.cast<String>() ?? [],
      descBulletsAm: (p['descBulletsAm'] as List?)?.cast<String>() ?? [],
      description: p['description'] as String?,
      descriptionAm: p['descriptionAm'] as String?,
      price: (p['price'] as num?)?.toDouble() ?? 0,
      discountedPrice: (p['discountedPrice'] as num?)?.toDouble(),
      category: category,
      images: images,
      colors: (p['colors'] as List?)?.cast<String>() ?? [],
      hidden: p['hidden'] == true,
      outOfStock: p['outOfStock'] == true,
    );
  }

  Map<String, dynamic> toCacheMap() => {
        'id': id,
        'name': name,
        'nameAm': nameAm,
        'descBullets': descBullets,
        'descBulletsAm': descBulletsAm,
        'description': description,
        'descriptionAm': descriptionAm,
        'price': price,
        'discountedPrice': discountedPrice,
        'category': category,
        'images': images,
        'colors': colors,
        'hidden': hidden,
        'outOfStock': outOfStock,
      };

  /// getDisplayPrice() equivalent from main-config.js
  double get displayPrice =>
      (discountedPrice != null && discountedPrice! < price) ? discountedPrice! : price;

  String get thumbnail => images.isNotEmpty ? images.first : '';

  /// Mirrors `isAm && p.nameAm ? p.nameAm : p.name` — used everywhere a
  /// product name is shown (card, detail sheet, cart, checkout, Telegram
  /// order text).
  String displayName(String lang) =>
      (lang == 'am' && nameAm != null && nameAm!.isNotEmpty) ? nameAm! : name;

  /// Mirrors the `bullets` fallback chain in openProduct() (main-actions.js):
  /// bullets → split description by newline → empty.
  List<String> displayBullets(String lang) {
    if (lang == 'am') {
      if (descBulletsAm.isNotEmpty) return descBulletsAm;
      if (descriptionAm != null && descriptionAm!.trim().isNotEmpty) {
        return descriptionAm!.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      }
    } else {
      if (descBullets.isNotEmpty) return descBullets;
      if (description != null && description!.trim().isNotEmpty) {
        return description!.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      }
    }
    return [];
  }
}

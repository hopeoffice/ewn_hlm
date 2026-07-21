// Ported 1:1 from `normalizeProduct()` in main-config.js so that the
// existing Firestore `products` collection needs NO changes.
class Product {
  final String id;
  final String name;
  final String nameEn;
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
    required this.nameEn,
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
      nameEn: p['name_en'] as String? ?? p['name'] as String? ?? '',
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
        'name_en': nameEn,
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
}

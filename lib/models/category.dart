// Ported 1:1 from CATEGORIES in main-config.js. Two sources feed this:
//   1) The static fallback list below (used before Firebase responds, or
//      if it's unreachable and no cache exists yet) — exact i18n strings
//      copied from the `am`/`en` dictionaries in main-config.js.
//   2) The live admin-managed list at Realtime DB `settings/categories`,
//      fetched by FirebaseService.fetchCategories() and cached locally by
//      StorageService.cacheCategories()/loadCachedCategories() — mirrors
//      loadCategoriesFromFirebase() / _applyCachedCategoriesIfAny() in
//      main-config.js. "all" is always pinned first, same as the web app.
class AppCategory {
  final String id;
  final String emoji;
  final String nameAm;
  final String nameEn;

  const AppCategory({
    required this.id,
    required this.emoji,
    required this.nameAm,
    required this.nameEn,
  });

  String label(String lang) => lang == 'en' ? nameEn : nameAm;

  factory AppCategory.fromMap(Map<dynamic, dynamic> m) {
    final nameEn = (m['nameEn'] ?? '').toString();
    return AppCategory(
      id: (m['value'] ?? m['id'] ?? '').toString(),
      emoji: (m['emoji'] ?? '🏷️').toString(),
      nameEn: nameEn,
      // Same fallback as the web: nameAm || nameEn.
      nameAm: (m['nameAm'] as String?)?.isNotEmpty == true ? m['nameAm'] as String : nameEn,
    );
  }

  Map<String, dynamic> toCacheMap() => {
        'value': id,
        'emoji': emoji,
        'nameEn': nameEn,
        'nameAm': nameAm,
      };
}

const AppCategory kAllCategory = AppCategory(id: 'all', emoji: '🛍️', nameAm: 'ሁሉም', nameEn: 'All');

const List<AppCategory> kDefaultCategories = [
  kAllCategory,
  AppCategory(id: 'phones', emoji: '📱', nameAm: 'ስልኮች', nameEn: 'Phones'),
  AppCategory(id: 'kitchen', emoji: '🍳', nameAm: 'የማእድቤት እቃዎች', nameEn: 'Kitchen'),
  AppCategory(id: 'laptops', emoji: '💻', nameAm: 'ላፕቶፕ', nameEn: 'Laptops'),
  AppCategory(id: 'beauty_health', emoji: '💄', nameAm: 'ውበት', nameEn: 'Beauty'),
  AppCategory(id: 'accessories', emoji: '🎮', nameAm: 'ልዩ ዕቃዎች', nameEn: 'Accessories'),
];

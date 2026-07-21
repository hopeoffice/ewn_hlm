// Ported 1:1 from CATEGORIES in main-config.js (fallback list shown
// before/independent of the Firebase-driven admin category list).
class AppCategory {
  final String id;
  final String emoji;
  final String label; // Amharic label (labelKey resolved to am string)

  const AppCategory({required this.id, required this.emoji, required this.label});
}

const List<AppCategory> kDefaultCategories = [
  AppCategory(id: 'all', emoji: '🛍️', label: 'ሁሉም'),
  AppCategory(id: 'phones', emoji: '📱', label: 'ስልኮች'),
  AppCategory(id: 'kitchen', emoji: '🍳', label: 'ኪችን'),
  AppCategory(id: 'laptops', emoji: '💻', label: 'ላፕቶፖች'),
  AppCategory(id: 'beauty_health', emoji: '💄', label: 'ውበት እና ጤና'),
  AppCategory(id: 'accessories', emoji: '🎮', label: 'መለዋወጫዎች'),
];

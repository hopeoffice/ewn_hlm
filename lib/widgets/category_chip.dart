import 'package:flutter/material.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';

/// Ported from .cat-chip in style.css.
class CategoryChip extends StatelessWidget {
  final AppCategory category;
  final bool active;
  final VoidCallback onTap;

  const CategoryChip({super.key, required this.category, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 70),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.accentSoft : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: active ? AppTheme.accent : Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? AppTheme.brand : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

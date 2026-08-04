import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small two-segment "አማ / Eng" pill, meant for the right side of an
/// AppBar, so the language can be switched right where it's needed
/// instead of only from the Profile menu.
class LangSwitcher extends StatelessWidget {
  final String currentLang; // 'am' or 'en'
  final ValueChanged<String> onChanged;

  const LangSwitcher({super.key, required this.currentLang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // This pill is used on AppBars/sheets that are themselves brand-green
    // (see AppTheme's appBarTheme). It used to rely on the *brand* color
    // for its border, unselected text, and even the transparent segment
    // fill — so on a green header everything but the selected label's
    // white text blended straight into the background and "disappeared".
    // Giving the pill its own white base fixes that regardless of what
    // it's placed on top of.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.brand, width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, 'አማ', 'am'),
          _segment(context, 'Eng', 'en'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, String code) {
    final selected = currentLang == code;
    return GestureDetector(
      onTap: () {
        if (!selected) onChanged(code);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppTheme.brand,
          ),
        ),
      ),
    );
  }
}

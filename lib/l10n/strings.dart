import 'strings_am.dart';
import 'strings_en.dart';

/// Equivalent of the `t(key)` helper in main-config.js, which reads from
/// `i18n[state.lang][key]`. Pass the current `AppState.lang` ('am'/'en').
class S {
  static String t(String key, String lang) {
    final map = lang == 'en' ? stringsEn : stringsAm;
    return map[key] ?? stringsAm[key] ?? key;
  }

  /// Mirrors formatPrice() in main-config.js:
  /// `n.toLocaleString('am-ET') + ' ' + t('etb')`. am-ET grouping is the
  /// same digit-grouping as en-US (thousands separator every 3 digits),
  /// so a plain manual grouping is equivalent here.
  static String formatPrice(num amount, String lang) {
    final rounded = amount.round();
    final digits = rounded.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final sign = rounded < 0 ? '-' : '';
    return '$sign${buf.toString()} ${t('etb', lang)}';
  }

  /// Same digit-grouping as formatPrice() but without a currency suffix —
  /// for the one place the web app hardcodes a literal "ETB" regardless
  /// of language (disc-prices in renderDiscountSection(), main-ui.js).
  static String formatNumber(num amount) {
    final rounded = amount.round();
    final digits = rounded.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buf.toString()}';
  }
}

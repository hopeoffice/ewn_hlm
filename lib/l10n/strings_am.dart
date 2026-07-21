/// Minimal port of the `i18n.am` / `i18n.en` maps in main-config.js.
/// Extend as screens are ported.
class S {
  static const Map<String, String> am = {
    'home': 'መነሻ',
    'cart': 'ጋሪ',
    'orders': 'ትዕዛዞች',
    'profile': 'መገለጫ',
    'etb': 'ብር',
    'login_title': 'እንኳን ደህና መጡ',
    'phone': 'ስልክ ቁጥር',
    'pin': 'ፓስዎርድ (4 ቁጥር)',
    'continue': 'ቀጥል',
    'login': 'ግባ',
    'register': 'ይመዝገቡ',
    'logout': 'ውጣ',
    'wallet': 'የኔ ዋሌት',
    'add_to_cart': 'ወደ ጋሪ ጨምር',
    'out_of_stock': 'ተሽጦ አልቋል',
    'empty_cart': 'ጋሪዎ ባዶ ነው',
    'connection_error': 'የግንኙነት ችግር፣ እባክዎ እንደገና ይሞክሩ',
  };

  static String t(String key) => am[key] ?? key;
}

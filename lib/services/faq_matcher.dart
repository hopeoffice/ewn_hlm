/// Ported from the FAQ matching pipeline in main-ui.js:
/// normalizeAmharic() + stemAmharic() + stemEnglish() + expandQuery()
/// (AM_SYNONYMS/EN_SYNONYMS) + matchFaqKeyword()'s tiered scorer.
///
/// The old `_bestMatch()` in HelpCenterScreen only did plain substring/
/// token overlap, so different inflected forms of the same Amharic word
/// (ይደርሳል / ደረሰ / ደርሷል — all "to arrive") scored as unrelated. This
/// file restores the web app's accuracy for Amharic queries specifically.
library faq_matcher;

/// Normalize Amharic text — maps variant/homophone forms to one
/// canonical base character, and collapses Ethiopic punctuation to a
/// space. Mirrors normalizeAmharic() in main-ui.js exactly.
String normalizeAmharic(String? str) {
  if (str == null || str.isEmpty) return '';
  var s = str
      .replaceAll(RegExp('[እዕ]'), 'እ')
      .replaceAll(RegExp('[አዓኣዐ]'), 'አ')
      .replaceAll(RegExp('[ሀሃሐሓኀኃ]'), 'ሀ')
      .replaceAll(RegExp('[ወዎ]'), 'ወ')
      .replaceAll(RegExp('[ጸፀ]'), 'ጸ')
      .replaceAll(RegExp('[ሰሠ]'), 'ሰ')
      .replaceAll(RegExp('[፣፤።]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s;
}

/// Amharic morphological stem — strips common verb/noun/possessive
/// suffixes. Mirrors stemAmharic() in main-ui.js exactly (same suffix
/// list, same order).
String stemAmharic(String? word) {
  if (word == null || word.length < 3) return word ?? '';
  var w = word;
  const suffixes = [
    'ዎታል', 'ልዎታ', 'ልዎ', 'ኛል', 'ናል', 'ዋል', 'ሏል', 'ታል', 'ቷል', 'ያል', 'ኣል', 'ሳል',
    'ኝ', 'ህ', 'ሽ', 'ን', 'ው', 'ት',
    'ዎች', 'ዎቹ', 'ዎቸ', 'ዎ', 'ዬ', 'ዩ', 'ዪ',
    'ዎን', 'ዎችን', 'ዬን',
  ];
  // JS chains .replace() calls unconditionally, in order — each one
  // operates on the *result* of the previous, not on the original word.
  // Reproduce that exactly (no early break) so results match 1:1.
  for (final suf in suffixes) {
    if (w.endsWith(suf)) {
      w = w.substring(0, w.length - suf.length);
    }
  }
  if (w.startsWith('እያ')) w = w.substring(2);
  if (w.startsWith('እየ')) w = w.substring(2);
  w = w.replaceFirst(RegExp('[ኩኪካኬ]\$'), 'ክ');
  w = w.replaceFirst(RegExp('[ሉሊሎሌ]\$'), 'ል');
  w = w.replaceFirst(RegExp('[ሩሪሮሬ]\$'), 'ር');
  return w;
}

/// English stemming (basic Porter-lite). Mirrors stemEnglish() in
/// main-ui.js exactly.
String stemEnglish(String? word) {
  if (word == null || word.length < 4) return word ?? '';
  var w = word;
  const rules = <String, String>{
    'ing': '', 'tion': '', 'tions': '', 'ness': '', 'ment': '', 'ments': '',
    'ities': 'ity', 'ies': 'y', 'ied': 'y', 'ed': '', 'er': '', 'ly': '', 's': '',
  };
  for (final entry in rules.entries) {
    if (w.endsWith(entry.key)) {
      w = w.substring(0, w.length - entry.key.length) + entry.value;
      break;
    }
  }
  return w;
}

/// Synonym / alias expansion tables — ported verbatim (meaning-for-
/// meaning) from AM_SYNONYMS / EN_SYNONYMS in main-ui.js.
const Map<String, List<String>> amSynonyms = {
  'ትዕዛዜ': ['ትዕዛዝ', 'ትዕዛዤ', 'ትዕዛዞ', 'ትዕዛዛ', 'orders', 'ያዘዝኩት', 'የግዢ ታሪክ'],
  'ትዕዛዝ': ['ትዕዛዜ', 'ትዕዛዤ', 'order', 'ግዢ'],
  'ትዕዛዤ': ['ትዕዛዝ', 'ትዕዛዜ'],
  'ያዘዝኩት': ['ትዕዛዜ', 'ትዕዛዝ', 'order'],
  'ይደርሳ': ['ይደርሳል', 'ይደርሱ', 'ደረሰ', 'ደርሷል', 'ደርሷ', 'ይደርስልኛል'],
  'ደርሷ': ['ደርሷል', 'ይደርሳል'],
  'ይምጣ': ['ይደርሳል', 'ይመጣ', 'ይጓዛ'],
  'ይደርስልኛል': ['ይደርሳል', 'ይደርሳ', 'ደርሷል'],
  'ቤት ድረስ': ['ቤቴ ድረስ', 'ቤት ድረስ', 'home delivery', 'doorstep', 'በራፍ ላይ'],
  'ስንት ቀን': ['ምን ያህል ቀን', 'ስንት ጊዜ', 'how long', 'how many days', 'ለመቼ'],
  'መቸ': ['መቼ', 'when', 'ለመቼ'],
  'ምን ያህል ቀን': ['ስንት ቀን', 'how long'],
  'ከፍያ': ['ክፍያ', 'payment', 'pay', 'ገንዘብ'],
  'ክፍያ': ['ከፍያ', 'payment', 'pay', 'ገንዘብ'],
  'ባንክ': ['bank', 'telebirr', 'cbe', 'awash', 'dashen', 'አቢሲንያ'],
  'ቴሌብር': ['telebirr', 'tele birr'],
  'አቢሲንያ': ['abyssinia', 'bank'],
  'እንዴት ይከፈላል': ['how to pay', 'የክፍያ ሂደት', 'ደረጃዎች'],
  'ሰርዝ': ['ሰርዘው', 'cancel', 'ሰርዘ', 'ማሰርዘ', 'መቀየር', 'አልፈልግም'],
  'ሰርዘ': ['ሰርዝ', 'cancel'],
  'ሰርዘው': ['ሰርዝ', 'ሰርዘ'],
  'አልፈልግም': ['ሰርዝ', 'cancel', 'ቀየርኩ ሀሳቤን'],
  'መልስ': ['ተመልስ', 'return', 'refund', 'ይመለሳ'],
  'ተመልስ': ['return', 'refund', 'መልስ'],
  'ገንዘቤ': ['refund', 'ይመለሳ', 'ሂሳብ', 'ገንዘቤ መልስ'],
  'ገንዘቤ መልስ': ['refund', 'ገንዘቤ', 'ሂሳብ ይመለስ'],
  'ሂሳብ ይመለስ': ['refund', 'ገንዘቤ', 'ይመለሳ'],
  'መቀየር': ['exchange', 'ተመልስ', 'ለውጥ', 'ቀየር'],
  'processing': ['ሂደት', 'processing', 'ቆሟ', 'ቆይቷ', 'ገና ነው'],
  'ቆሟ': ['processing', 'ቆይቷ', 'ያልተቀየረ', 'ገና ነው'],
  'ገና ነው': ['processing', 'ቆሟ', 'ስንት ይቆያል'],
  'ክትትል': ['track', 'status', 'ሁኔታ', 'የት ነው', 'አሁን የት'],
  'ተሰበረ': ['broken', 'damaged', 'ጉዳት', 'ተበላሸ'],
  'ጉዳት': ['broken', 'damaged', 'ተሰበረ', 'defect', 'ተበላሸ'],
  'ተበላሸ': ['broken', 'damaged', 'ተሰበረ', 'አልሰራም'],
  'አልሰራም': ['not working', 'ተበላሸ', 'ችግር አለበት'],
  'ተሳሳተ': ['wrong', 'incorrect', 'ስህተት', 'ሌላ ምርት', 'ያልጠየኩት'],
  'ስህተት': ['wrong', 'mistake', 'ተሳሳተ'],
  'ሌላ ምርት': ['wrong', 'different item', 'ተሳሳተ'],
  'ሂሳብ': ['account', 'ሒሳብ', 'refund', 'ይመለሳ'],
  'ሒሳብ': ['account', 'ሂሳብ'],
  'መረጃ ቀይር': ['edit profile', 'ስም ቀይር', 'አስተካክል'],
  'አግኙ': ['contact', 'reach', 'ያነጋግሩ'],
  'ያነጋግሩ': ['contact', 'አግኙ'],
  'ድጋፍ': ['support', 'help', 'ያነጋግሩ', 'እርዳታ'],
  'እርዳታ': ['support', 'help', 'ድጋፍ'],
  'ሰላም': ['selam', 'hello', 'hi'],
  'አመሰግናለሁ': ['thanks', 'thank you', 'amesegnalew'],
};

const Map<String, List<String>> enSynonyms = {
  'order': ['orders', 'purchase', 'buy', 'bought', 'placed'],
  'orders': ['order', 'purchase', 'history', 'past orders'],
  'deliver': ['delivery', 'arrive', 'ship', 'shipping', 'dispatch'],
  'delivery': ['deliver', 'arrive', 'ship', 'shipment', 'eta'],
  'arrive': ['delivery', 'come', 'receive', 'when will', 'eta'],
  'cancel': ['cancellation', 'undo', 'stop order', 'remove order', 'changed my mind', 'void'],
  'pay': ['payment', 'paid', 'checkout', 'pay with'],
  'payment': ['pay', 'paid', 'method', 'bank', 'payment options'],
  'refund': ['money back', 'return', 'reimbursement', 'my money', 'get money back'],
  'return': ['refund', 'exchange', 'send back', 'dont like it'],
  'broken': ['damaged', 'defective', 'cracked', 'faulty', 'not working'],
  'damaged': ['broken', 'defective', 'ruined', 'faulty'],
  'wrong': ['incorrect', 'different', 'mistake', 'not what i ordered', 'swap'],
  'track': ['status', 'where', 'tracking', 'order status', 'current status'],
  'stuck': ['not moving', 'processing', 'delayed', 'still processing'],
  'delayed': ['late', 'slow', 'overdue', 'taking long', 'taking forever', 'hasnt arrived'],
  'account': ['register', 'sign up', 'login', 'profile'],
  'contact': ['support', 'help', 'reach', 'customer service', 'talk to someone'],
  'install': ['download', 'add to home', 'pwa', 'add icon', 'shortcut'],
  'password': ['forgot', 'reset', 'cant login', 'otp', 'lost access'],
  'where': ['location', 'track', 'status', 'where is', 'find my order'],
  'discount': ['sale', 'offer', 'cheaper', 'promo', 'go on sale'],
  'secure': ['safe', 'safety', 'protected', 'trust', 'privacy', 'encryption'],
  'duplicate': ['double', 'charged twice', 'billing error', 'charged again'],
  'notification': ['alert', 'notify', 'push', 'bell icon', 'keep me updated'],
  'color': ['colour', 'colors', 'colours', 'variant', 'options'],
  'stock': ['available', 'in stock', 'out of stock', 'inventory', 'do you have'],
  'search': ['find', 'look for', 'browse'],
  'cart': ['basket', 'items disappeared', 'missing items'],
  'warranty': ['guarantee', 'covered defect', 'guarantee period'],
  'thanks': ['thank you', 'appreciate', 'grateful'],
  'hello': ['hi', 'hey', 'good morning', 'good day'],
};

/// Ported from expandQuery() in main-ui.js.
Set<String> expandQuery(List<String> tokens, String lang) {
  final synonyms = lang == 'en' ? enSynonyms : amSynonyms;
  final stemFn = lang == 'en' ? stemEnglish : stemAmharic;
  final expanded = <String>{...tokens};
  for (final tok in tokens) {
    final syns = synonyms[tok];
    if (syns != null) {
      for (final s in syns) {
        expanded.add(s.toLowerCase());
      }
    }
    final stemmed = stemFn(tok);
    if (stemmed != tok && stemmed.length > 2) {
      expanded.add(stemmed);
      final stemSyns = synonyms[stemmed];
      if (stemSyns != null) {
        for (final s in stemSyns) {
          expanded.add(s.toLowerCase());
        }
      }
    }
  }
  return expanded;
}

/// Detect which language a free-typed message is in, by counting
/// Ethiopic vs Latin letters. Mirrors detectInputLang() in main-ui.js.
/// Returns null when there's no signal (numbers/symbols only).
String? detectInputLang(String? text) {
  if (text == null || text.isEmpty) return null;
  var amCount = 0, enCount = 0;
  for (final rune in text.runes) {
    if (rune >= 0x1200 && rune <= 0x137F) {
      amCount++;
    } else if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      enCount++;
    }
  }
  if (amCount == 0 && enCount == 0) return null;
  return amCount >= enCount ? 'am' : 'en';
}

/// Ported from matchFaqKeyword()'s scoreAgainst() + tier logic in
/// main-ui.js, including the THRESHOLD=2 cutoff. `faqs` entries use the
/// same field names as assets/faq_data.json / settings/faq (question,
/// answer, keywords, question_en, answer_en, keywords_en, category).
Map<String, dynamic>? bestFaqMatch(List<Map<String, dynamic>> faqs, String input, String lang) {
  if (input.isEmpty || faqs.isEmpty) return null;
  final isEn = lang == 'en';
  final stemFn = isEn ? stemEnglish : stemAmharic;

  final raw = input.toLowerCase().trim();
  final q = normalizeAmharic(raw);
  final tokens = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
  if (tokens.isEmpty && q.length < 2) return null;

  final expanded = expandQuery(tokens, lang);
  const threshold = 2;

  int scoreAgainst(Map<String, dynamic> faq) {
    var score = 0;

    final question = normalizeAmharic(
        ((isEn ? faq['question_en'] : null) ?? faq['question'] ?? '').toString().toLowerCase());
    final answer = normalizeAmharic(
        ((isEn ? faq['answer_en'] : null) ?? faq['answer'] ?? '').toString().toLowerCase());
    final keywordsRaw = (isEn ? faq['keywords_en'] : null) ?? faq['keywords'];
    final keywords = keywordsRaw is List ? keywordsRaw.map((k) => k.toString()).toList() : <String>[];

    // Tier 1: exact full-query match
    if (question == q) return 100;

    // Tier 2: full query substring in question
    if (question.contains(q) && q.length > 2) score += 12;

    // Tier 3: question word tokens
    final qWords = question.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final qStems = qWords.map(stemFn).toList();

    for (final tok in tokens) {
      final tokStem = stemFn(tok);
      if (qWords.contains(tok)) {
        score += 5;
        continue;
      }
      if (qStems.contains(tokStem) && tokStem.length > 2) {
        score += 4;
        continue;
      }
      if (qWords.any((w) => w.contains(tok) && tok.length > 3)) {
        score += 2;
        continue;
      }
      if (qWords.any((w) => tok.contains(w) && w.length > 3)) {
        score += 1;
      }
    }

    // Tier 4: keyword matching (exact + stem + expanded)
    final kwNorms = keywords.map((kw) => normalizeAmharic(kw.toLowerCase())).toList();
    final kwStems = kwNorms.map(stemFn).toList();

    for (final tok in expanded) {
      final tokStem = stemFn(tok);
      for (var i = 0; i < kwNorms.length; i++) {
        final kwl = kwNorms[i];
        final kwStem = kwStems[i];
        if (tok == kwl) {
          score += 8;
          break;
        }
        if (tokStem == kwStem && tokStem.length > 2) {
          score += 6;
          break;
        }
        if (tok.contains(kwl) && kwl.length > 2) {
          score += 5;
          break;
        }
        if (kwl.contains(tok) && tok.length > 2) {
          score += 4;
          break;
        }
        if (kwStem.contains(tokStem) && tokStem.length > 3) {
          score += 3;
          break;
        }
        if (tokStem.contains(kwStem) && kwStem.length > 3) {
          score += 2;
          break;
        }
      }
    }

    // Tier 5: answer text light match (bonus only)
    if (q.length > 3 && answer.contains(q)) score += 3;
    for (final tok in tokens) {
      if (tok.length > 3 && answer.contains(tok)) score += 1;
    }

    return score;
  }

  Map<String, dynamic>? best;
  var bestScore = 0;
  for (final faq in faqs) {
    final s = scoreAgainst(faq);
    if (s > bestScore) {
      bestScore = s;
      best = faq;
    }
  }
  return bestScore >= threshold ? best : null;
}

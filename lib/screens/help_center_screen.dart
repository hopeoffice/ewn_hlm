import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../widgets/offline_overlay.dart';
import '../services/firebase_service.dart';
import '../services/faq_matcher.dart';

/// Ported from #screen-help-center / renderHelpCenter() chatbot in
/// main-ui.js. FAQs load from Firebase (settings/faq) first, falling
/// back to the bundled assets/faq_data.json — same order as the PWA.
/// Matching uses the full ported pipeline in faq_matcher.dart (Amharic
/// normalization, stemming, synonym expansion — same as matchFaqKeyword()
/// in main-ui.js).
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

/// HC_PAGE_SIZE in main-ui.js — 5 FAQ chips shown per category page,
/// with a "Show more" chip to reveal the next page.
const _hcPageSize = 5;

class _ChatMsg {
  final bool fromUser;
  final String text;
  // Mutable (not final): once a newer chip-bearing bot message is added,
  // BUGFIX — previously each old bot message kept its chips forever, so
  // stale category/question chips from earlier in the conversation stayed
  // tappable and visually piled up as the chat grew (old categories were
  // never cleared before new ones got written further down the chat). We
  // now null this out on superseded messages so only the most recent bot
  // message ever shows live chips — mirroring the web app's single
  // floating #hc-faq-chips element, which is always removed before a new
  // one is appended.
  List<Map<String, dynamic>>? chips;
  // Only set for category-question-list messages, so a later language
  // toggle can rebuild the same page of the same category in the new
  // language (see _refreshLiveChipsLang()).
  final String? chipsCategoryId;
  final int chipsPage;
  _ChatMsg.user(this.text)
      : fromUser = true,
        chips = null,
        chipsCategoryId = null,
        chipsPage = 0;
  _ChatMsg.bot(this.text, {this.chips, this.chipsCategoryId, this.chipsPage = 0}) : fromUser = false;
}

const _categories = [
  ('orders', '📦', 'ትዕዛዞች', 'Orders'),
  ('payment', '💳', 'ክፍያ', 'Payment'),
  ('delivery', '🚚', 'ደሊቨሪ', 'Delivery'),
  ('products', '🛍️', 'ምርቶች', 'Products'),
  ('cart', '🛒', 'ጋሪ', 'Cart'),
  // Added to match HC_CATEGORIES in main-ui.js — the web app's FAQ set
  // gained 13 wallet/coin questions (faq_051–faq_063) that need their
  // own browsable category, otherwise they're only reachable via a
  // lucky free-text match.
  ('wallet', '💰', 'ዋሌት / ኮይን', 'Wallet / Coins'),
  ('security', '🔒', 'ደህንነት', 'Security'),
  ('general', 'ℹ️', 'አጠቃላይ', 'General'),
];

/// Ported from `HC_SUPPORT_CATEGORIES` in main-ui.js — FAQ categories
/// where the bot also offers a "Customer Support team" escalation button
/// alongside the FAQ answer, since these topics are the most likely to
/// need a real human (order status, delivery, payment issues, and now
/// wallet/coin issues since real money is involved).
const _supportCategories = {'orders', 'delivery', 'payment', 'wallet'};

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  List<Map<String, dynamic>> _faqs = [];
  final _messages = <_ChatMsg>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = true;

  // Ported from `_hcLang` in main-ui.js — the Help Center chatbot's own
  // language toggle, independent of the app-wide language (state.lang).
  // null = follow the app language; once the person taps the toggle it
  // stays pinned to whatever they picked, same as the web app.
  String? _hcLang;

  /// Ported from hcGetLang() in main-ui.js.
  String _currentLang() => _hcLang ?? context.read<AppState>().lang;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Firebase first (settings/faq) — matches loadFaqFromFirebase() in
    // main-ui.js, so FAQ edits from the admin panel reach the app without
    // a store release. Bundled assets/faq_data.json is only the fallback.
    try {
      final remote = await FirebaseService().fetchFaqs();
      if (remote != null && remote.isNotEmpty) {
        _faqs = remote;
      } else {
        _faqs = await _loadBundledFaqs();
      }
    } catch (_) {
      _faqs = await _loadBundledFaqs();
    }
    final lang = _currentLang();
    setState(() {
      _loading = false;
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_1', lang)));
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_2', lang), chips: _categoryChips(lang)));
    });
  }

  /// Ported from hcToggleLang() in main-ui.js — flips the Help Center's
  /// own language and re-renders whichever chip set is currently live
  /// (category list or a category's question page) in the new language,
  /// without retranslating the rest of the chat history.
  void _toggleHcLang() {
    setState(() {
      _hcLang = _currentLang() == 'am' ? 'en' : 'am';
      _refreshLiveChipsLang(_hcLang!);
    });
  }

  /// Rebuilds the chips on the most recent bot message (if it has any) in
  /// [lang] — category chips become the translated category list; a
  /// question page becomes the same category/page re-fetched in [lang].
  void _refreshLiveChipsLang(String lang) {
    if (_messages.isEmpty) return;
    final last = _messages.last;
    if (last.fromUser || last.chips == null || last.chips!.isEmpty) return;
    if (last.chipsCategoryId != null) {
      last.chips = _questionsForCategory(last.chipsCategoryId!, lang, last.chipsPage);
    } else if (last.chips!.first['kind'] == 'category') {
      last.chips = _categoryChips(lang);
    } else {
      last.chips = _answerChips(last.chips!.any((c) => c['kind'] == 'support') ? 'orders' : null, lang);
    }
  }

  /// BUGFIX (see _ChatMsg.chips doc) — clears chips off every earlier
  /// message before a new chip-bearing message is added, so only the
  /// latest bot message ever has live, tappable chips. Call this right
  /// before appending any new message.
  void _clearStaleChips() {
    for (final m in _messages) {
      m.chips = null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadBundledFaqs() async {
    try {
      final raw = await rootBundle.loadString('assets/faq_data.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.entries.map((e) => {'id': e.key, ...(e.value as Map<String, dynamic>)}).toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _categoryChips(String lang) {
    return _categories.map((c) => {'kind': 'category', 'id': c.$1, 'emoji': c.$2, 'label': lang == 'en' ? c.$4 : c.$3}).toList();
  }

  /// Ported from hcShowQuestionsForCategory() in main-ui.js — 5 questions
  /// per page (HC_PAGE_SIZE), with a "Show more" chip appended when more
  /// remain and a "Back to categories" chip always appended.
  List<Map<String, dynamic>> _questionsForCategory(String cat, String lang, int page) {
    final catFaqs = _faqs.where((f) => f['category'] == cat).toList();
    final start = page * _hcPageSize;
    final slice = catFaqs.skip(start).take(_hcPageSize);
    final hasMore = catFaqs.length > start + _hcPageSize;

    final chips = slice.map((f) {
      final q = lang == 'en' ? (f['question_en'] ?? f['question']) : f['question'];
      return {'kind': 'question', 'id': f['id'], 'label': q.toString()};
    }).toList();

    if (hasMore) {
      chips.add({'kind': 'more', 'catId': cat, 'page': page + 1, 'label': S.t('hc_show_more', lang)});
    }
    chips.add({'kind': 'back', 'label': S.t('hc_back_cats', lang)});
    return chips;
  }

  void _onChipTap(Map<String, dynamic> chip, String lang) {
    if (chip['kind'] == 'category') {
      setState(() {
        _clearStaleChips();
        _messages.add(_ChatMsg.user('${chip['emoji']} ${chip['label']}'));
        _messages.add(_ChatMsg.bot(S.t('hc_faq_chips_label', lang),
            chips: _questionsForCategory(chip['id'] as String, lang, 0),
            chipsCategoryId: chip['id'] as String));
      });
    } else if (chip['kind'] == 'more') {
      // "Show more" — same category, next page. Ported from the
      // page+1 call in hcShowQuestionsForCategory()'s "hc-more-chip".
      final catId = chip['catId'] as String;
      final page = chip['page'] as int;
      setState(() {
        _clearStaleChips();
        _messages.add(_ChatMsg.bot(S.t('hc_faq_chips_label', lang),
            chips: _questionsForCategory(catId, lang, page), chipsCategoryId: catId, chipsPage: page));
      });
    } else if (chip['kind'] == 'back') {
      // "Back to categories" — ported from hcShowCategoryChips().
      setState(() {
        _clearStaleChips();
        _messages.add(_ChatMsg.bot(S.t('hc_cat_label', lang), chips: _categoryChips(lang)));
      });
    } else if (chip['kind'] == 'support') {
      _showSupportStep(lang);
    } else if (chip['kind'] == 'send_to_admin') {
      _openAdminForm(lang);
    } else {
      final faq = _faqs.firstWhere((f) => f['id'] == chip['id'], orElse: () => {});
      if (faq.isEmpty) return;
      final answer = lang == 'en' ? (faq['answer_en'] ?? faq['answer']) : faq['answer'];
      setState(() {
        // BUGFIX: previously the "5 questions" bot message (with its
        // chips) stayed in the chat log after one was tapped, so the
        // old chips kept accumulating on screen and could still be
        // tapped, showing an answer in the "wrong place" relative to
        // what the user just asked. Once a question is chosen, remove
        // that preceding question-list message so the screen is left
        // with only the asked question + its answer, as requested.
        if (_messages.isNotEmpty && !_messages.last.fromUser && _messages.last.chips != null) {
          _messages.removeLast();
        }
        _clearStaleChips();
        _messages.add(_ChatMsg.user(chip['label'] as String));
        _messages.add(_ChatMsg.bot(answer.toString(),
            chips: _answerChips(faq['category'] as String?, lang)));
      });
    }
    _scrollToBottom();
  }

  /// Ported from the inline "hc-support-btn" appended to matched answers
  /// in main-ui.js: category chips as usual, but with a "Customer
  /// Support team" chip prepended when the FAQ's category is one of
  /// `_supportCategories`.
  List<Map<String, dynamic>> _answerChips(String? category, String lang) {
    final chips = _categoryChips(lang);
    if (category != null && _supportCategories.contains(category)) {
      return [
        {'kind': 'support', 'label': S.t('hc_contact_support', lang)},
        ...chips,
      ];
    }
    return chips;
  }

  /// Ported from hcShowSupportStep() in main-ui.js.
  void _showSupportStep(String lang) {
    setState(() {
      _clearStaleChips();
      _messages.add(_ChatMsg.bot(
        S.t('hc_contact_support_msg', lang),
        chips: [
          {'kind': 'send_to_admin', 'label': S.t('hc_send_to_admin_btn', lang)},
        ],
      ));
    });
    _scrollToBottom();
  }

  /// Ported from hcShowAdminForm()/hcSendToAdmin() in main-ui.js — shows
  /// a small form (as a modal bottom sheet here rather than an inline
  /// textarea appended to the chat, since Flutter's ListView of
  /// stateless chat bubbles isn't a natural place for a live text
  /// input) and pushes to Firebase `support/` with the same 24h
  /// per-phone rate limit as the web app.
  Future<void> _openAdminForm(String lang) async {
    final ctrl = TextEditingController();
    bool sending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.t('hc_admin_form_title', lang), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: S.t('hc_admin_placeholder', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                onPressed: sending
                    ? null
                    : () async {
                        final msg = ctrl.text.trim();
                        if (msg.isEmpty) {
                          ScaffoldMessenger.of(sheetContext)
                              .showSnackBar(SnackBar(content: Text(S.t('hc_type_msg', lang))));
                          return;
                        }
                        if (!await requireOnlineOrWarn(sheetContext, lang)) return;
                        setSheetState(() => sending = true);
                        final err = await context.read<AppState>().sendSupportMessage(msg);
                        if (!mounted) return;
                        if (err == null) {
                          Navigator.of(sheetContext).pop();
                          setState(() => _messages.add(_ChatMsg.bot(S.t('hc_admin_sent', lang))));
                          _scrollToBottom();
                        } else {
                          setSheetState(() => sending = false);
                          final toast = err == 'rate_limited' ? S.t('hc_rate_limit', lang) : S.t('hc_admin_error', lang);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(toast)));
                        }
                      },
                child: sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                    : Text(S.t('hc_admin_send', lang), style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ported from matchFaqKeyword() in main-ui.js — Amharic normalization,
  /// morphological stemming, and synonym expansion, via faq_matcher.dart.
  Map<String, dynamic>? _bestMatch(String input, String lang) {
    return bestFaqMatch(_faqs, input, lang);
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final lang = _currentLang();
    _inputCtrl.clear();
    setState(() {
      _clearStaleChips();
      _messages.add(_ChatMsg.user(text));
    });

    final match = _bestMatch(text, lang);
    setState(() {
      if (match != null) {
        final answer = lang == 'en' ? (match['answer_en'] ?? match['answer']) : match['answer'];
        _messages.add(_ChatMsg.bot(answer.toString(), chips: _answerChips(match['category'] as String?, lang)));
      } else {
        _messages.add(_ChatMsg.bot(S.t('hc_no_match', lang), chips: _categoryChips(lang)));
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the app language changes (so it still tracks it while
    // no manual Help Center override is set), but _currentLang() prefers
    // _hcLang once the person has tapped the toggle — ported from
    // hcGetLang() in main-ui.js.
    context.watch<AppState>().lang;
    final lang = _currentLang();

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: Text(S.t('hc_title', lang)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        actions: [
          // Ported from .hc-lang-btn / hcToggleLang() in main-ui.js — the
          // Help Center previously had no way to switch its own language
          // at all.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: _toggleHcLang,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.brand,
                  side: const BorderSide(color: AppTheme.brand, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(S.t('hc_lang_switch', lang),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _buildBubble(_messages[i], lang),
                  ),
                ),
                _buildInputBar(lang),
              ],
            ),
    );
  }

  Widget _buildBubble(_ChatMsg m, String lang) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // BUGFIX: the web app always shows a small bot avatar
                // (hc-bot-icon) to the left of every bot bubble via
                // hcAddMessage(); Flutter had no equivalent at all, so bot
                // replies looked anonymous. Now uses the provided chatbot
                // icon asset instead of the fallback emoji.
                if (!m.fromUser) ...[
                  Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(right: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppTheme.tagBg(context), shape: BoxShape.circle),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/icons/icon_chatbot.png', width: 26, height: 26, fit: BoxFit.cover),
                  ),
                ],
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: m.fromUser ? AppTheme.brand : AppTheme.card(context),
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: m.fromUser ? null : Border.all(color: AppTheme.line(context)),
                    ),
                    child: Text(m.text,
                        style: TextStyle(color: m.fromUser ? Colors.white : AppTheme.text(context), fontSize: 14, height: 1.4)),
                  ),
                ),
              ],
            ),
          ),
          if (m.chips != null && m.chips!.isNotEmpty) _buildChipGroup(m.chips!, lang),
        ],
      ),
    );
  }

  /// Ported from .hc-chips / .hc-chips-col in main-ui.js's injected CSS.
  /// Question chips stack in a tight vertical column (gap 6, like
  /// .hc-chips-col), while category/support/nav chips wrap in a row (gap
  /// 8, like the default .hc-chips). BUGFIX: previously every chip used
  /// Flutter's default Material ActionChip, whose built-in minimum touch
  /// target (~48dp tall) made rows of wrapped chips — and every stacked
  /// question — look far more spaced out than the compact web design.
  /// These are now plain tight Containers instead.
  Widget _buildChipGroup(List<Map<String, dynamic>> chips, String lang) {
    final questionChips = chips.where((c) => c['kind'] == 'question').toList();
    final navChips = chips.where((c) => c['kind'] == 'more' || c['kind'] == 'back').toList();
    final otherChips = chips.where((c) => c['kind'] != 'question' && c['kind'] != 'more' && c['kind'] != 'back').toList();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (questionChips.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < questionChips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _hcChip(questionChips[i]['label'] as String, () => _onChipTap(questionChips[i], lang),
                      fullWidth: true, outline: false),
                ],
              ],
            ),
          if (navChips.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: questionChips.isNotEmpty ? 4 : 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: navChips.map((c) {
                  final isMore = c['kind'] == 'more';
                  return _hcChip(c['label'] as String, () => _onChipTap(c, lang), filled: isMore, muted: !isMore);
                }).toList(),
              ),
            ),
          if (otherChips.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: questionChips.isNotEmpty || navChips.isNotEmpty ? 6 : 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: otherChips.map((c) {
                  final label = c['kind'] == 'category' ? '${c['emoji']} ${c['label']}' : c['label'] as String;
                  return _hcChip(label, () => _onChipTap(c, lang), outline: c['kind'] == 'category');
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact pill button — mirrors .hc-chip's tight CSS padding (7px
  /// 14px, 20px radius) instead of Material's roomier default chip.
  Widget _hcChip(String label, VoidCallback onTap,
      {bool fullWidth = false, bool outline = false, bool filled = false, bool muted = false}) {
    final Color bg = filled ? AppTheme.brand : AppTheme.card(context);
    final Color fg = filled
        ? Colors.white
        : outline
            ? AppTheme.brand
            : muted
                ? AppTheme.textMuted(context)
                : AppTheme.text(context);
    final Color borderColor = filled
        ? Colors.transparent
        : outline
            ? AppTheme.brand
            : AppTheme.line(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: outline ? 1.5 : 1),
          ),
          child: Text(label,
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 12.5, color: fg, fontWeight: outline || filled ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildInputBar(String lang) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          border: Border(top: BorderSide(color: AppTheme.line(context))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: S.t('hc_input_placeholder', lang),
                  filled: true,
                  fillColor: AppTheme.bg(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppTheme.brand,
              child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 18), onPressed: _send),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}

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

class _ChatMsg {
  final bool fromUser;
  final String text;
  final List<Map<String, dynamic>>? chips; // suggested FAQ chips, bot-only
  _ChatMsg.user(this.text)
      : fromUser = true,
        chips = null;
  _ChatMsg.bot(this.text, {this.chips}) : fromUser = false;
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
    final lang = mounted ? context.read<AppState>().lang : 'am';
    setState(() {
      _loading = false;
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_1', lang)));
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_2', lang), chips: _categoryChips(lang)));
    });
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

  List<Map<String, dynamic>> _questionsForCategory(String cat, String lang) {
    return _faqs.where((f) => f['category'] == cat).take(6).map((f) {
      final q = lang == 'en' ? (f['question_en'] ?? f['question']) : f['question'];
      return {'kind': 'question', 'id': f['id'], 'label': q.toString()};
    }).toList();
  }

  void _onChipTap(Map<String, dynamic> chip, String lang) {
    if (chip['kind'] == 'category') {
      setState(() {
        _messages.add(_ChatMsg.user('${chip['emoji']} ${chip['label']}'));
        _messages.add(_ChatMsg.bot(S.t('hc_faq_chips_label', lang), chips: _questionsForCategory(chip['id'], lang)));
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
    final lang = context.read<AppState>().lang;
    _inputCtrl.clear();
    setState(() => _messages.add(_ChatMsg.user(text)));

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
    final lang = context.watch<AppState>().lang;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: Text(S.t('hc_title', lang)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
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
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
          if (m.chips != null && m.chips!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: m.chips!.map((c) {
                  final label = c['kind'] == 'category' ? '${c['emoji']} ${c['label']}' : c['label'] as String;
                  return ActionChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.accentSoft,
                    onPressed: () => _onChipTap(c, lang),
                  );
                }).toList(),
              ),
            ),
        ],
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

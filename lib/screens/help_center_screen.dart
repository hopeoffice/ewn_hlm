import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';

/// Ported from #screen-help-center / renderHelpCenter() chatbot in
/// main-ui.js. Uses the same assets/faq_data.json bundled with the app
/// (fallback source in the PWA too) with a simplified keyword-overlap
/// scorer standing in for the full stemmer/synonym-expansion pipeline —
/// good enough to route common questions to the right FAQ answer.
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
  ('security', '🔒', 'ደህንነት', 'Security'),
  ('general', 'ℹ️', 'አጠቃላይ', 'General'),
];

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
    try {
      final raw = await rootBundle.loadString('assets/faq_data.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _faqs = map.entries.map((e) => {'id': e.key, ...(e.value as Map<String, dynamic>)}).toList();
    } catch (_) {
      _faqs = [];
    }
    final lang = mounted ? context.read<AppState>().lang : 'am';
    setState(() {
      _loading = false;
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_1', lang)));
      _messages.add(_ChatMsg.bot(S.t('hc_greeting_2', lang), chips: _categoryChips(lang)));
    });
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
    } else {
      final faq = _faqs.firstWhere((f) => f['id'] == chip['id'], orElse: () => {});
      if (faq.isEmpty) return;
      final answer = lang == 'en' ? (faq['answer_en'] ?? faq['answer']) : faq['answer'];
      setState(() {
        _messages.add(_ChatMsg.user(chip['label'] as String));
        _messages.add(_ChatMsg.bot(answer.toString(), chips: _categoryChips(lang)));
      });
    }
    _scrollToBottom();
  }

  /// Simplified stand-in for the JS scoreAgainst()/expandQuery() pipeline:
  /// counts keyword/question/answer token overlap rather than full
  /// Amharic stemming + synonym expansion.
  Map<String, dynamic>? _bestMatch(String input, String lang) {
    final q = input.toLowerCase().trim();
    if (q.isEmpty) return null;
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();

    Map<String, dynamic>? best;
    int bestScore = 0;
    for (final faq in _faqs) {
      final question = (lang == 'en' ? (faq['question_en'] ?? faq['question']) : faq['question']).toString().toLowerCase();
      final answer = (lang == 'en' ? (faq['answer_en'] ?? faq['answer']) : faq['answer']).toString().toLowerCase();
      final keywords = ((lang == 'en' ? faq['keywords_en'] : faq['keywords']) as List? ?? [])
          .map((k) => k.toString().toLowerCase())
          .toList();

      int score = 0;
      if (question == q) score += 100;
      if (question.contains(q) && q.length > 2) score += 12;
      for (final tok in tokens) {
        if (question.contains(tok)) score += 4;
        for (final kw in keywords) {
          if (tok == kw) {
            score += 8;
          } else if (tok.contains(kw) || kw.contains(tok)) {
            score += 4;
          }
        }
        if (tok.length > 3 && answer.contains(tok)) score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = faq;
      }
    }
    return bestScore >= 4 ? best : null;
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
        _messages.add(_ChatMsg.bot(answer.toString(), chips: _categoryChips(lang)));
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
      backgroundColor: AppTheme.bgMain,
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
                color: m.fromUser ? AppTheme.brand : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: m.fromUser ? null : Border.all(color: AppTheme.border),
              ),
              child: Text(m.text,
                  style: TextStyle(color: m.fromUser ? Colors.white : AppTheme.textPrimary, fontSize: 14, height: 1.4)),
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
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: S.t('hc_input_placeholder', lang),
                  filled: true,
                  fillColor: AppTheme.bgMain,
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

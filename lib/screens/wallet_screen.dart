import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/wallet_service.dart';
import '../models/coin_rate_model.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../widgets/offline_overlay.dart';
import '../widgets/coin_candlestick_chart.dart';

/// Ported from renderMyAccount() (balance) + openBuyCoinsModal()/
/// submitBuyCoins() (buy form) + renderTransactionHistoryScreen()
/// (main-coins.js). NOTE: the old version of this screen had a
/// standalone "Redeem" button that doesn't exist on the web app at all —
/// coins are only ever spent as a checkout discount (see
/// checkout_screen.dart), never redeemed directly from here.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;

    // Same bonus/savings estimate as renderMyAccount() — there is only
    // ONE real balance (coins); "Bonus" is a display-only breakdown of
    // how much of it came from signup+referrals vs money purchases.
    final bonusNominal = app.referralCount * WalletService.referralCoins + WalletService.signupBonusCoins;
    final bonusCoins = bonusNominal < app.coins ? bonusNominal : app.coins;
    final savingsCoins = (app.coins - bonusCoins).clamp(0, app.coins);

    return Scaffold(
      appBar: AppBar(title: Text(lang == 'am' ? '💰 የኔ አካውንት' : '💰 My Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Balance card ----
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.brand, AppTheme.brandLight]),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              children: [
                Text(lang == 'am' ? 'ጠቅላላ ቀሪ ሂሳብ' : 'Total Coin Balance',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('🪙 ${S.formatNumber(app.coins)}',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                Text('≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _balanceChip(lang == 'am' ? 'ጉርሻ' : 'Bonus', bonusCoins)),
                    const SizedBox(width: 10),
                    Expanded(child: _balanceChip(lang == 'am' ? 'ቁጠባ' : 'Savings', savingsCoins)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Wallet / Transaction History quick actions ----
          // ✅ Ported from the 2026-07-25 web revision: these used to be
          // two small semi-transparent icon buttons in the balance
          // card's header row (hard to see against the green gradient).
          // The web app pulled them out into their own white cards right
          // below the balance card instead — mirrored here.
          Row(
            children: [
              Expanded(
                child: _quickActionCard(
                  context,
                  icon: '💱',
                  label: lang == 'am' ? 'ዋሌት' : 'Wallet',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CoinWalletScreen())),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickActionCard(
                  context,
                  icon: '🧾',
                  label: lang == 'am' ? 'ትራንዛክሽን ታሪክ' : 'Transaction History',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => showBuyCoinsSheet(context),
              icon: const Text('🪙'),
              label: Text(lang == 'am' ? 'coin ግዛ' : 'Buy Coins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard(BuildContext context, {required String icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: AppTheme.card(context),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.line(context)),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 5),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.text(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceChip(String label, int coins) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            Text('${S.formatNumber(coins)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

/// Ported from renderTransactionHistoryScreen() (main-coins.js) — its own
/// full page (`#screen-transaction-history`), separate from "My Account".
/// Previously this feed was rendered inline on WalletScreen itself; split
/// out here so the wallet page stays short and this page can grow/scroll
/// independently, matching the web app's navigation structure.
class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';

    return Scaffold(
      appBar: AppBar(title: Text(isAm ? '🧾 ትራንዛክሽን ታሪክ' : '🧾 Transaction History')),
      body: app.coinFeed.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧾', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(isAm ? 'እስካሁን ምንም ትራንዛክሽን የለም' : 'No transactions yet',
                      style: TextStyle(color: AppTheme.textMuted(context))),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: app.coinFeed.map((item) => _FeedRow(item: item, lang: lang)).toList(),
            ),
    );
  }
}

/// Ported from TX_TYPE_INFO + renderPendingFeedRow()/renderTxFeedRow() in
/// main-coins.js.
const _kTxTypeInfo = {
  'earn_signup': ('🎁', 'የምዝገባ ማበረታቻ', 'Signup bonus'),
  'earn_referral': ('🔗', 'የሪፈራል Coins', 'Referral coins'),
  'redeem': ('🛒', 'በግዢ ላይ ጥቅም ላይ ውሏል', 'Used at checkout'),
  'purchase_approved': ('🪙', 'Coin ግዢ ጸደቀ', 'Coin purchase approved'),
  'admin_add': ('➕', 'በአድሚን ታክሏል', 'Added by admin'),
  'admin_deduct': ('➖', 'በአድሚን ተቀንሷል', 'Deducted by admin'),
  // ✅ Added for the 💱 Wallet screen (Sell/Transfer) — ported from the
  // extended TX_TYPE_INFO in main-coins.js.
  'sell_approved': ('💸', 'Coin ሽያጭ ጸደቀ', 'Coin sell approved'),
  'transfer_out': ('↗️', 'ወደ ሌላ ሰው ተልኳል', 'Sent to another user'),
  'transfer_in': ('↙️', 'ከሌላ ሰው ደርሷል', 'Received from another user'),
};

class _FeedRow extends StatelessWidget {
  final CoinFeedItem item;
  final String lang;
  const _FeedRow({required this.item, required this.lang});

  @override
  Widget build(BuildContext context) {
    final isAm = lang == 'am';
    final time = item.time > 0 ? DateTime.fromMillisecondsSinceEpoch(item.time) : null;
    final timeStr = time != null ? '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '';

    String title;
    String amountLabel;
    Color amountColor;
    String? orderBit;
    String? reasonBit;
    double etbValue;

    switch (item.kind) {
      case CoinFeedKind.pendingBuy:
        title = isAm ? '🪙 Coin ግዢ ጥያቄ' : '🪙 Coin purchase request';
        amountLabel = '+${S.formatNumber(item.coins)} 🕓 ${isAm ? 'በመጠባበቅ ላይ' : 'Pending'}';
        amountColor = AppTheme.gold;
        etbValue = WalletService.coinsToEtb(item.coins).toDouble();
        break;
      case CoinFeedKind.pendingSell:
        title = isAm ? '🪙 Coin ሽያጭ ጥያቄ' : '🪙 Coin sell request';
        amountLabel = '-${S.formatNumber(item.coins)} 🕓 ${isAm ? 'በመጠባበቅ ላይ' : 'Pending'}';
        amountColor = AppTheme.gold;
        etbValue = item.etbAmount;
        break;
      case CoinFeedKind.rejectedBuy:
        title = isAm ? '🪙 Coin ግዢ ጥያቄ' : '🪙 Coin purchase request';
        amountLabel = '+${S.formatNumber(item.coins)} ❌ ${isAm ? 'ውድቅ ተደርጓል' : 'Rejected'}';
        amountColor = AppTheme.danger;
        reasonBit = item.rejectReason;
        etbValue = WalletService.coinsToEtb(item.coins).toDouble();
        break;
      case CoinFeedKind.rejectedSell:
        title = isAm ? '🪙 Coin ሽያጭ ጥያቄ' : '🪙 Coin sell request';
        amountLabel = '-${S.formatNumber(item.coins)} ❌ ${isAm ? 'ውድቅ ተደርጓል' : 'Rejected'}';
        amountColor = AppTheme.danger;
        reasonBit = item.rejectReason;
        etbValue = item.etbAmount;
        break;
      case CoinFeedKind.tx:
        final info = _kTxTypeInfo[item.type] ?? ('🪙', item.type, item.type);
        title = '${info.$1} ${isAm ? info.$2 : info.$3}';
        final positive = item.amount > 0;
        final absAmount = item.amount.abs();
        amountLabel = positive
            ? '+${S.formatNumber(absAmount)} ${isAm ? 'Coin ተቀብለዋል' : 'Coin received'}'
            : '-${S.formatNumber(absAmount)} ${isAm ? 'Coin ከፍለዋል' : 'Coin Paid'}';
        amountColor = positive ? AppTheme.accent : AppTheme.danger;
        if (item.orderId != null) {
          orderBit = '🧾 ${item.orderId}${item.orderPercent != null ? ' · ${item.orderPercent}% ${isAm ? 'በCoin ተከፍሏል' : 'paid by Coin'}' : ''}';
        }
        etbValue = WalletService.coinsToEtb(absAmount).toDouble();
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.line(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (orderBit != null) Text(orderBit, style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                if (reasonBit != null && reasonBit.isNotEmpty)
                  Text('💬 $reasonBit', style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                Text(timeStr, style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amountLabel, style: TextStyle(color: amountColor, fontWeight: FontWeight.bold, fontSize: 12)),
              Text('≈ ${S.formatPrice(etbValue, lang)}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  BUY COINS FORM — openBuyCoinsModal()/submitBuyCoins() (main-coins.js)
// ============================================================

const _kPaymentMethods = [
  ('telebirr', '📱', 'ቴሌብር', 'Telebirr', '0932208224'),
  ('cbe', '🏦', 'ንግድ ባንክ (CBE)', 'CBE (Commercial Bank)', '1000123456789'),
  ('abyssinia', '🏦', 'አቢሲኒያ ባንክ', 'Bank of Abyssinia', '40987654321'),
];

/// Ported from the `.co-coin-note` danger-styled warning block added to
/// the Buy/Sell/Transfer modals in the 2026-07-25 web revision.
Widget _dangerNote(BuildContext context, String text) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: AppTheme.danger), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      child: Text(text, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
    );

/// Ported from the `#bc-confirm-check`/`#sc-confirm-check`/`#tc-confirm-check`
/// checkbox added alongside each danger note — the submit button stays
/// disabled until this is ticked.
Widget _confirmCheckbox(BuildContext context, {required bool value, required String label, required ValueChanged<bool?> onChanged}) => InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const SizedBox(width: 4),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: AppTheme.text(context)))),
          ],
        ),
      ),
    );

Future<void> showBuyCoinsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BuyCoinsSheet(),
  );
}

class _BuyCoinsSheet extends StatefulWidget {
  const _BuyCoinsSheet();
  @override
  State<_BuyCoinsSheet> createState() => _BuyCoinsSheetState();
}

class _BuyCoinsSheetState extends State<_BuyCoinsSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _selectedMethod = 'telebirr';
  XFile? _receipt;
  Uint8List? _receiptPreview;
  bool _submitting = false;
  bool _confirmed = false;
  bool _nameInvalid = false;
  bool _amountInvalid = false;
  bool _receiptInvalid = false;
  String? _receiptError;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = context.read<AppState>().user?.name ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amountETB => double.tryParse(_amountCtrl.text.trim()) ?? 0;
  int get _previewCoins => WalletService.etbToCoins(_amountETB);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';
    final method = _kPaymentMethods.firstWhere((m) => m.$1 == _selectedMethod);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(18),
          children: [
            Text(isAm ? '🪙 coin ግዛ' : '🪙 Buy Coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(isAm ? '1 coin = 0.068 ${S.t('etb', lang)}' : '1 Coin = 0.068 ${S.t('etb', lang)}',
                style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12)),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(child: _field(isAm ? 'ሙሉ ስም' : 'FULL NAME', _nameCtrl, invalid: _nameInvalid, onChanged: (_) => setState(() => _nameInvalid = false))),
              const SizedBox(width: 10),
              Expanded(
                child: _labeled(
                  isAm ? 'ስልክ ቁጥር' : 'PHONE NUMBER',
                  TextField(
                    controller: TextEditingController(text: app.user?.phone ?? ''),
                    readOnly: true,
                    style: TextStyle(color: AppTheme.textMuted(context)),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(
                child: _labeled(
                  isAm ? 'መጠን (ብር)' : 'AMOUNT (ETB)',
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _amountInvalid = false),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: isAm ? 'ቢያንስ ${WalletService.minBuyCoinsEtb.toInt()}' : 'min ${WalletService.minBuyCoinsEtb.toInt()}',
                      errorBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                      enabledBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _labeled(
                  isAm ? 'የክፍያ ዘዴ ▼' : 'PAYMENT METHOD ▼',
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMethod,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: _kPaymentMethods
                        .map((m) => DropdownMenuItem(value: m.$1, child: Text('${m.$2} ${isAm ? m.$3 : m.$4}', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMethod = v ?? _selectedMethod),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                isAm ? 'ዝቅተኛ ግዢ ${WalletService.minBuyCoinsEtb.toInt()} ብር ነው' : 'Minimum purchase is ${WalletService.minBuyCoinsEtb.toInt()} ETB',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context)),
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(method.$5, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: method.$5));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('co_copy', lang)), duration: const Duration(seconds: 1)));
                    },
                    child: Text(S.t('co_copy', lang), style: const TextStyle(color: AppTheme.brand, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _labeled(
                  isAm ? 'ደረሰኝ ፎቶ *' : 'RECEIPT SCREENSHOT *',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickReceipt,
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: _receiptInvalid ? AppTheme.danger : AppTheme.line(context)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _receipt == null
                              ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.grey))
                              : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_receiptPreview!, fit: BoxFit.cover)),
                        ),
                      ),
                      if (_receiptError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_receiptError!,
                              style: TextStyle(fontSize: 11, color: _receiptInvalid ? AppTheme.danger : Colors.green)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 100,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Text('🪙 ${S.formatNumber(_previewCoins)}\n${isAm ? 'coin ያገኛሉ' : 'coins'}',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            _dangerNote(
              context,
              isAm
                  ? '⚠️ ለአካውንትዎ ደህንነት ፓስዎርድ በፍጹም ለማንም አያጋሩ። የተሳሳተ ወይም የውሸት ደረሰኝ መላክ ትዕዛዙ ውድቅ እንዲሆን እና አካውንትዎ እንዲታገድ ያደርጋል። ማረጋገጫ 1–5 ሰዓት ሊፈጅ ይችላል።'
                  : "⚠️ For your account's security, never share your password with anyone. Submitting an incorrect or fake receipt will get the request rejected and may get your account suspended. Confirmation may take 1–5 hours.",
            ),
            _confirmCheckbox(
              context,
              value: _confirmed,
              label: isAm ? 'መረጃው ትክክለኛ መሆኑን አረጋግጣለሁ' : 'I confirm this information is accurate',
              onChanged: (v) => setState(() => _confirmed = v ?? false),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: (_submitting || !_confirmed) ? null : () => _submit(context, app, method),
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                    : Text(isAm ? 'ላክ ለማረጋገጫ' : 'Send for Confirmation', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted(context))),
          const SizedBox(height: 4),
          child,
        ],
      );

  Widget _field(String label, TextEditingController ctrl, {bool invalid = false, ValueChanged<String>? onChanged}) {
    return _labeled(
      label,
      TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          errorBorder: invalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
          enabledBorder: invalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
        ),
      ),
    );
  }

  /// Ported from handleReceiptUpload() in main-actions.js — see the same
  /// fix in checkout_screen.dart's _pickReceipt() for details.
  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final lang = context.read<AppState>().lang;

    final mime = picked.mimeType ?? '';
    final looksLikeImage = mime.startsWith('image/') ||
        RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false).hasMatch(picked.path);
    if (!looksLikeImage) {
      setState(() {
        _receipt = null;
        _receiptPreview = null;
        _receiptInvalid = true;
        _receiptError = S.t('co_receipt_type', lang);
      });
      return;
    }

    final bytes = await picked.readAsBytes();
    if (bytes.length > 1024 * 1024) {
      setState(() {
        _receipt = null;
        _receiptPreview = null;
        _receiptInvalid = true;
        _receiptError = S.t('co_receipt_large', lang);
      });
      return;
    }

    setState(() {
      _receipt = picked;
      _receiptPreview = bytes;
      _receiptInvalid = false;
      _receiptError = S.t('co_receipt_valid', lang);
    });
  }

  Future<void> _submit(BuildContext context, AppState app, (String, String, String, String, String) method) async {
    final lang = app.lang;
    final isAm = lang == 'am';
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _nameInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? 'እባክዎ ሙሉ ስም ያስገቡ' : 'Please enter your full name')));
      return;
    }
    if (_amountETB <= 0) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? 'እባክዎ መጠን ያስገቡ' : 'Please enter an amount')));
      return;
    }
    if (_amountETB < WalletService.minBuyCoinsEtb) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAm
              ? '🪙 coin ለመግዛት ዝቅተኛ መጠን ${WalletService.minBuyCoinsEtb.toInt()} ብር ነው'
              : '🪙 Minimum amount to buy coins is ${WalletService.minBuyCoinsEtb.toInt()} ETB')));
      return;
    }
    if (_receipt == null) {
      setState(() => _receiptInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('co_upload_receipt', lang))));
      return;
    }
    if (!await requireOnlineOrWarn(context, lang)) return;

    setState(() => _submitting = true);
    final bytes = await _receipt!.readAsBytes();
    final ok = await app.submitBuyCoins(
      name: name,
      amountETB: _amountETB,
      paymentMethodLabel: isAm ? method.$3 : method.$4,
      receiptBytes: bytes,
      receiptFilename: _receipt!.name,
    );
    setState(() => _submitting = false);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isAm ? '✅ ተልኳል! አድሚን እስኪያረጋግጥ ይጠብቁ።' : '✅ Sent! Waiting for admin confirmation.')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(isAm ? 'ስህተት ተፈጥሯል፣ እንደገና ይሞክሩ' : 'Something went wrong, please try again')));
    }
  }
}

// ============================================================
//  💱 WALLET SCREEN — ported from ensureWalletScreen()/openWalletScreen()/
//  renderWalletScreen() in main-coins.js. A separate, richer page from
//  "My Account" above: live buy/sell coin rate, a decorative candlestick
//  chart, and the Buy/Sell/Transfer actions.
// ============================================================
class CoinWalletScreen extends StatefulWidget {
  const CoinWalletScreen({super.key});
  @override
  State<CoinWalletScreen> createState() => _CoinWalletScreenState();
}

class _CoinWalletScreenState extends State<CoinWalletScreen> {
  late Future<CoinRateData> _rateFuture;

  @override
  void initState() {
    super.initState();
    _rateFuture = context.read<AppState>().fetchCoinRateData();
  }

  void _reload() => setState(() => _rateFuture = context.read<AppState>().fetchCoinRateData());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';

    return Scaffold(
      appBar: AppBar(title: Text('💱 ${isAm ? 'ዋሌት' : 'Wallet'}')),
      body: FutureBuilder<CoinRateData>(
        future: _rateFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rate = snap.data!;
          final current = rate.current;
          final firstEntry = rate.history.first;
          final changePct = firstEntry.buyRate > 0 ? ((current.buyRate - firstEntry.buyRate) / firstEntry.buyRate) * 100 : 0.0;
          final changeUp = changePct >= 0;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(isAm ? 'ቀሪ ሂሳብ' : 'balance', style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('🪙 ${S.formatNumber(app.coins)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)}',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- Price card + chart ----
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.card(context),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.line(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Text('🪙', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 6),
                            const Text('Ewn Coin', style: TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_formatRate(current.buyRate, lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (changeUp ? Colors.green : AppTheme.danger).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${changeUp ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: changeUp ? Colors.green[800] : AppTheme.danger),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CoinCandlestickChart(currentPrice: current.buyRate, isUp: changeUp, seedKey: current.updatedAt),
                      const SizedBox(height: 8),
                      Row(children: [
                        _legendDot(const Color(0xFF2F6FED)),
                        Text(' ${isAm ? 'የግዢ ዋጋ' : 'Buy price'}: ${_formatRate(current.buyRate, lang)}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                        const SizedBox(width: 14),
                        _legendDot(const Color(0xFFE63946)),
                        Text(' ${isAm ? 'የሽያጭ ዋጋ' : 'Sell price'}: ${_formatRate(current.sellRate, lang)}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Actions ----
                Row(
                  children: [
                    Expanded(child: _walletActionBtn(context, '➕', isAm ? 'ግዛ' : 'Buy', AppTheme.gold, () => showBuyCoinsSheet(context))),
                    const SizedBox(width: 10),
                    Expanded(child: _walletActionBtn(context, '➖', isAm ? 'ሽጥ' : 'Sell', AppTheme.danger, () => showSellCoinsSheet(context, current.sellRate))),
                    const SizedBox(width: 10),
                    Expanded(child: _walletActionBtn(context, '↔️', isAm ? 'አስተላልፍ' : 'Transfer', AppTheme.brand, () => showTransferCoinsSheet(context))),
                  ],
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Text(
                    isAm
                        ? 'coin ግዢ እና ሽያጭ ላይ ሂሳብዎን ወደ ዋሌትዎ ወይም ወደ ባንክ ቁጥርዎ ለማስተላለፍ ከ1 - 5 ሰአት ሊወስድ ይችላል።'
                        : 'Transferring your balance to your wallet or bank account after a coin buy/sell may take 1–5 hours.',
                    style: TextStyle(fontSize: 12, color: AppTheme.text(context)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _legendDot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _walletActionBtn(BuildContext context, String icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coin-rate values need up to 4 decimal places (e.g. 0.0680 ETB), unlike
/// S.formatPrice() which rounds ETB order totals to whole numbers — ported
/// from the plain `formatPrice(current.buyRate)` call in
/// renderWalletScreen() (JS `toLocaleString` keeps up to 3 fraction
/// digits by default for non-integers).
String _formatRate(double rate, String lang) {
  var s = rate.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$s ${S.t('etb', lang)}';
}

// ============================================================
//  WALLET PASSWORD CONFIRM — ported from openWalletPinModal()/
//  confirmWalletPin() in main-coins.js. Unified here into a single
//  async dialog (Flutter doesn't need the open/close/callback dance the
//  DOM version used) that re-verifies the password server-side via
//  AppState.verifyPassword() (POST /verifyPassword) before Sell/Transfer
//  proceed. Returns the confirmed password, or null if cancelled.
// ============================================================
Future<String?> promptWalletPassword(BuildContext context, String subtitle) async {
  final passwordCtrl = TextEditingController();
  final lang = context.read<AppState>().lang;
  final isAm = lang == 'am';
  bool loading = false;
  String? error;

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(isAm ? '🔒 ፓስዎርድ ያረጋግጡ' : '🔒 Confirm Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: TextStyle(color: AppTheme.textMuted(dialogContext))),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(labelText: S.t('pin_code', lang), border: const OutlineInputBorder(), counterText: ''),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(isAm ? 'ይቅር' : 'Cancel')),
          ElevatedButton(
            onPressed: loading
                ? null
                : () async {
                    final pwd = passwordCtrl.text.trim();
                    if (pwd.length != 4) {
                      setState(() => error = isAm ? 'የ4 አሃዝ ፓስዎርድ ያስገቡ' : 'Enter your 4-digit password');
                      return;
                    }
                    setState(() {
                      loading = true;
                      error = null;
                    });
                    final err = await dialogContext.read<AppState>().verifyPassword(pwd);
                    if (err == null) {
                      Navigator.of(dialogContext).pop(pwd);
                    } else {
                      setState(() {
                        loading = false;
                        error = err == 'locked_try_later'
                            ? (isAm ? '⚠️ ብዙ ጊዜ ተሳስተዋል፣ ከጥቂት ደቂቃዎች በኋላ ይሞክሩ' : '⚠️ Too many attempts, try again later')
                            : (isAm ? '❌ የተሳሳተ ፓስዎርድ' : '❌ Incorrect password');
                      });
                    }
                  },
            child: loading
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isAm ? 'አረጋግጥ' : 'Confirm'),
          ),
        ],
      ),
    ),
  );
  return result;
}

// ============================================================
//  SELL COINS — ported from openSellCoinsModal()/submitSellCoinsRequest()
//  in main-coins.js. Same "pending request, admin approves" pattern as
//  Buy Coins: the client never deducts its own balance directly.
// ============================================================
Future<void> showSellCoinsSheet(BuildContext context, double sellRate) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SellCoinsSheet(sellRate: sellRate),
  );
}

class _SellCoinsSheet extends StatefulWidget {
  final double sellRate;
  const _SellCoinsSheet({required this.sellRate});
  @override
  State<_SellCoinsSheet> createState() => _SellCoinsSheetState();
}

class _SellCoinsSheetState extends State<_SellCoinsSheet> {
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  String _selectedMethod = 'telebirr';
  bool _submitting = false;
  bool _confirmed = false;
  bool _amountInvalid = false;
  bool _accountInvalid = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  int get _coins => int.tryParse(_amountCtrl.text.trim()) ?? 0;
  double get _previewEtb => double.parse((_coins * widget.sellRate).toStringAsFixed(2));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';
    final method = _kPaymentMethods.firstWhere((m) => m.$1 == _selectedMethod);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(18),
          children: [
            Text(isAm ? '🪙 coin ሽጥ' : '🪙 Sell Coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              child: Column(children: [
                _summaryRow(isAm ? '1 coin' : '1 Coin', '${widget.sellRate} ${S.t('etb', lang)}'),
                const SizedBox(height: 4),
                _summaryRow(isAm ? 'ያለዎት ቀሪ ሂሳብ' : 'Your Balance', '🪙 ${S.formatNumber(app.coins)}'),
              ]),
            ),
            const SizedBox(height: 14),

            _labeled(
              isAm ? 'የሚሸጡት coin ብዛት' : 'COINS TO SELL',
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _amountInvalid = false),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: isAm ? 'ቢያንስ ${WalletService.minSellCoins}' : 'min ${WalletService.minSellCoins}',
                  errorBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                  enabledBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _labeled(
              isAm ? 'የክፍያ መቀበያ ዘዴ ▼' : 'RECEIVE PAYMENT VIA ▼',
              DropdownButtonFormField<String>(
                initialValue: _selectedMethod,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: _kPaymentMethods
                    .map((m) => DropdownMenuItem(value: m.$1, child: Text('${m.$2} ${isAm ? m.$3 : m.$4}', overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMethod = v ?? _selectedMethod),
              ),
            ),
            const SizedBox(height: 10),
            _labeled(
              isAm ? 'የሚቀበሉበት ሂሳብ ቁጥር *' : 'YOUR ACCOUNT NUMBER *',
              TextField(
                controller: _accountCtrl,
                onChanged: (_) => setState(() => _accountInvalid = false),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: isAm ? 'የቴሌብር/ባንክ ቁጥርዎ' : 'Telebirr / bank number',
                  errorBorder: _accountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                  enabledBorder: _accountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              child: Text('${S.formatPrice(_previewEtb, lang)}\n${isAm ? 'ያገኛሉ' : 'you get'}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 18),

            _dangerNote(
              context,
              isAm
                  ? '⚠️ የገባ ሂሳብ ቁጥር ትክክል መሆኑን ያረጋግጡ። ማረጋገጫ 1–5 ሰዓት ሊፈጅ ይችላል። ከጸደቀ በኋላ ትዕዛዙ ሊቀለበስ አይችልም፣ የተሳሳተ ሂሳብ ቁጥር በሰጡ ጊዜ ገንዘቡ ላይመለስ ይችላል።'
                  : "⚠️ Double-check the account number you entered. Confirmation may take 1–5 hours. Once approved, this can't be reversed — an incorrect account number may mean the money can't be recovered.",
            ),
            _confirmCheckbox(
              context,
              value: _confirmed,
              label: isAm ? 'መረጃው ትክክለኛ መሆኑን አረጋግጣለሁ' : 'I confirm this information is accurate',
              onChanged: (v) => setState(() => _confirmed = v ?? false),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: (_submitting || !_confirmed) ? null : () => _submit(context, app, method),
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                    : Text(isAm ? 'ላክ ለማረጋገጫ' : 'Send for Confirmation', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))],
      );

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted(context))),
          const SizedBox(height: 4),
          child,
        ],
      );

  Future<void> _submit(BuildContext context, AppState app, (String, String, String, String, String) method) async {
    final lang = app.lang;
    final isAm = lang == 'am';
    final account = _accountCtrl.text.trim();

    if (_coins < WalletService.minSellCoins) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAm ? '⚠️ ዝቅተኛ ሽያጭ መጠን ${WalletService.minSellCoins} coin ነው' : '⚠️ Minimum sale is ${WalletService.minSellCoins} coins')));
      return;
    }
    if (_coins > app.coins) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ በቂ coin የለዎትም' : "⚠️ You don't have enough coins")));
      return;
    }
    if (account.isEmpty) {
      setState(() => _accountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ የሂሳብ ቁጥርዎን ያስገቡ' : '⚠️ Please enter your account number')));
      return;
    }
    if (!await requireOnlineOrWarn(context, lang)) return;

    final password = await promptWalletPassword(context, isAm ? 'coin ለመሸጥ ፓስዎርድዎን ያስገቡ' : 'Enter your password to sell coins');
    if (password == null || !mounted) return;

    setState(() => _submitting = true);
    final ok = await app.submitSellCoins(
      coins: _coins,
      sellRate: widget.sellRate,
      paymentMethodLabel: isAm ? method.$3 : method.$4,
      account: account,
    );
    setState(() => _submitting = false);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isAm ? '✅ ተልኳል! አድሚን እስኪያረጋግጥ ይጠብቁ።' : '✅ Sent! Waiting for admin confirmation.')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(isAm ? 'ስህተት ተፈጥሯል፣ እንደገና ይሞክሩ' : 'Something went wrong, please try again')));
    }
  }
}

// ============================================================
//  TRANSFER COINS — ported from openTransferCoinsModal()/
//  submitTransferCoins() in main-coins.js. Immediate, user-to-user;
//  enforced server-side by the Worker (POST /transferCoins), so no admin
//  approval step (unlike Buy/Sell).
// ============================================================
Future<void> showTransferCoinsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TransferCoinsSheet(),
  );
}

class _TransferCoinsSheet extends StatefulWidget {
  const _TransferCoinsSheet();
  @override
  State<_TransferCoinsSheet> createState() => _TransferCoinsSheetState();
}

class _TransferCoinsSheetState extends State<_TransferCoinsSheet> {
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _submitting = false;
  bool _confirmed = false;
  bool _phoneInvalid = false;
  bool _amountInvalid = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _coins => int.tryParse(_amountCtrl.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(18),
          children: [
            Text(isAm ? '↔️ coin አስተላልፍ' : '↔️ Transfer Coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isAm ? 'ያለዎት ቀሪ ሂሳብ' : 'Your Balance', style: const TextStyle(fontSize: 12)),
                  Text('🪙 ${S.formatNumber(app.coins)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 14),

            _labeled(
              context,
              isAm ? 'ተቀባይ ስልክ ቁጥር *' : 'RECIPIENT PHONE *',
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() => _phoneInvalid = false),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '09xxxxxxxx',
                  errorBorder: _phoneInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                  enabledBorder: _phoneInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _labeled(
              context,
              isAm ? 'coin ብዛት *' : 'COINS *',
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _amountInvalid = false),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: isAm ? 'ቢያንስ ${WalletService.minTransferCoins}' : 'min ${WalletService.minTransferCoins}',
                  errorBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                  enabledBorder: _amountInvalid ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger)) : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('≈ ${S.formatPrice(WalletService.coinsToEtb(_coins), lang)}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
            ),
            const SizedBox(height: 18),

            _dangerNote(
              context,
              isAm
                  ? '⚠️ ይህ ወዲያውኑ ይፈጸማል እና ወደ ተሳሳተ ቁጥር ከተላከ መመለስ አይቻልም — የተቀባዩን ስልክ ቁጥር በጥንቃቄ ያረጋግጡ።'
                  : "⚠️ This happens instantly and can't be undone if sent to the wrong number — double-check the recipient's phone number.",
            ),
            _confirmCheckbox(
              context,
              value: _confirmed,
              label: isAm ? 'የተቀባዩን ቁጥር አረጋግጫለሁ' : "I've verified the recipient's number",
              onChanged: (v) => setState(() => _confirmed = v ?? false),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: (_submitting || !_confirmed) ? null : () => _submit(context, app),
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                    : Text(isAm ? 'አስተላልፍ' : 'Transfer', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(BuildContext context, String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted(context))),
          const SizedBox(height: 4),
          child,
        ],
      );

  Future<void> _submit(BuildContext context, AppState app) async {
    final lang = app.lang;
    final isAm = lang == 'am';
    final toPhone = _phoneCtrl.text.trim();

    if (!AppState.ethioPhoneRe.hasMatch(toPhone)) {
      setState(() => _phoneInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ ትክክለኛ ስልክ ቁጥር ያስገቡ' : '⚠️ Enter a valid phone number')));
      return;
    }
    if (toPhone == app.user?.phone) {
      setState(() => _phoneInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ ወደ ራስዎ ማስተላለፍ አይቻልም' : "⚠️ Can't transfer to your own number")));
      return;
    }
    if (_coins < WalletService.minTransferCoins) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAm ? '⚠️ ዝቅተኛ ማስተላለፊያ መጠን ${WalletService.minTransferCoins} coin ነው' : '⚠️ Minimum transfer is ${WalletService.minTransferCoins} coins')));
      return;
    }
    if (_coins > app.coins) {
      setState(() => _amountInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ በቂ coin የለዎትም' : "⚠️ You don't have enough coins")));
      return;
    }
    if (!await requireOnlineOrWarn(context, lang)) return;

    final password = await promptWalletPassword(context, isAm ? 'coin ለማስተላለፍ ፓስዎርድዎን ያስገቡ' : 'Enter your password to transfer coins');
    if (password == null || !mounted) return;

    setState(() => _submitting = true);
    final err = await app.transferCoins(toPhone: toPhone, coins: _coins, password: password);
    setState(() => _submitting = false);
    if (!mounted) return;

    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isAm ? '✅ ${S.formatNumber(_coins)} coin ተልኳል!' : '✅ ${S.formatNumber(_coins)} coins sent!')));
    } else {
      final msg = err == 'recipient_not_found'
          ? (isAm ? '⚠️ ተቀባዩ አልተመዘገበም' : '⚠️ Recipient not registered')
          : err == 'insufficient_balance'
              ? (isAm ? '⚠️ በቂ coin የለዎትም' : "⚠️ You don't have enough coins")
              : err == 'wrong_password'
                  ? (isAm ? '❌ የተሳሳተ ፓስዎርድ' : '❌ Incorrect password')
                  : err == 'send_limit_reached'
                      ? (isAm ? '⚠️ በ24 ሰዓት ውስጥ ከ3 ጊዜ በላይ መላክ አይችሉም' : '⚠️ You can only send up to 3 transfers per 24 hours')
                      : err == 'recipient_limit_reached'
                          ? (isAm
                              ? '⚠️ ተቀባዩ በ24 ሰዓት ውስጥ ከ3 ጊዜ በላይ መቀበል አይችልም'
                              : '⚠️ Recipient can only receive up to 3 transfers per 24 hours')
                          : err == 'value_cap_exceeded'
                              ? (isAm
                                  ? '⚠️ በ48 ሰዓት ውስጥ ከ20,000 ብር በላይ ማስተላለፍ አይቻልም'
                                  : "⚠️ You can't transfer more than 20,000 ETB worth within 48 hours")
                              : (isAm ? 'ስህተት ተፈጥሯል' : 'Something went wrong');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

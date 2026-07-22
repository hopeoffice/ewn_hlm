import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';

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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => showBuyCoinsSheet(context),
              icon: const Text('🪙'),
              label: Text(lang == 'am' ? 'coin ግዛ' : 'Buy Coins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Transaction history (renderTransactionHistoryScreen) ----
          Text(lang == 'am' ? '🧾 ትራንዛክሽን ታሪክ' : '🧾 Transaction History',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (app.coinFeed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    const Text('🧾', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(lang == 'am' ? 'እስካሁን ምንም ትራንዛክሽን የለም' : 'No transactions yet',
                        style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else
            ...app.coinFeed.map((item) => _FeedRow(item: item, lang: lang)),
        ],
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

/// Ported from TX_TYPE_INFO + renderPendingFeedRow()/renderTxFeedRow() in
/// main-coins.js.
const _kTxTypeInfo = {
  'earn_signup': ('🎁', 'የምዝገባ ማበረታቻ', 'Signup bonus'),
  'earn_referral': ('🔗', 'የሪፈራል Coins', 'Referral coins'),
  'redeem': ('🛒', 'በግዢ ላይ ጥቅም ላይ ውሏል', 'Used at checkout'),
  'purchase_approved': ('🪙', 'Coin ግዢ ጸደቀ', 'Coin purchase approved'),
  'admin_add': ('➕', 'በአድሚን ታክሏል', 'Added by admin'),
  'admin_deduct': ('➖', 'በአድሚን ተቀንሷል', 'Deducted by admin'),
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

    if (item.isPending) {
      title = isAm ? '🪙 Coin ግዢ ጥያቄ' : '🪙 Coin purchase request';
      amountLabel = '+${S.formatNumber(item.coins)} 🕓 ${isAm ? 'በመጠባበቅ ላይ' : 'Pending'}';
      amountColor = AppTheme.gold;
      orderBit = null;
    } else {
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
    }

    final etbValue = item.isPending ? item.coins : item.amount.abs();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (orderBit != null) Text(orderBit, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                Text(timeStr, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amountLabel, style: TextStyle(color: amountColor, fontWeight: FontWeight.bold, fontSize: 12)),
              Text('≈ ${S.formatPrice(WalletService.coinsToEtb(etbValue), lang)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
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
  bool _nameInvalid = false;
  bool _amountInvalid = false;
  bool _receiptInvalid = false;

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
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(18),
          children: [
            Text(isAm ? '🪙 coin ግዛ' : '🪙 Buy Coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(isAm ? '1 coin = 0.068 ${S.t('etb', lang)}' : '1 Coin = 0.068 ${S.t('etb', lang)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
                    style: const TextStyle(color: AppTheme.textSecondary),
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
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
                  GestureDetector(
                    onTap: _pickReceipt,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: _receiptInvalid ? AppTheme.danger : AppTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _receipt == null
                          ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.grey))
                          : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_receiptPreview!, fit: BoxFit.cover)),
                    ),
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

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _submitting ? null : () => _submit(context, app, method),
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
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
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

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _receipt = picked;
      _receiptPreview = bytes;
      _receiptInvalid = false;
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

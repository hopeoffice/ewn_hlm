import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';

/// Ported from PAYMENT_METHODS in main-actions.js. NOTE: these are the
/// same fallback numbers the web app itself hardcodes at load time —
/// both apps then call loadPaymentAccountsFromDb() to overwrite them
/// from Realtime DB settings/paymentAccounts if the admin has set custom
/// ones, which is wired up in _CheckoutScreenState.initState() below.
class _PaymentMethod {
  final String id;
  final String emoji;
  final String nameAm;
  final String nameEn;
  String account;
  final String accountLabelAm;
  final String accountLabelEn;
  _PaymentMethod(this.id, this.emoji, this.nameAm, this.nameEn, this.account,
      this.accountLabelAm, this.accountLabelEn);

  String name(String lang) => lang == 'en' ? nameEn : nameAm;
  String accountLabel(String lang) => lang == 'en' ? accountLabelEn : accountLabelAm;
}

final _paymentMethods = [
  _PaymentMethod('telebirr', '📱', 'ቴሌብር', 'Telebirr', '0932208224',
      'ℹ️ ቴሌብር የንግድ ስልክ (MERCHANT ACCOUNT)', 'ℹ️ Telebirr Merchant Number'),
  _PaymentMethod('cbe', '🏦', 'ንግድ ባንክ (CBE)', 'CBE (Commercial Bank)', '1000123456789',
      'ℹ️ የንግድ ባንክ አካውንት ቁጥር (CBE)', 'ℹ️ CBE Account Number'),
  _PaymentMethod('abyssinia', '🏦', 'አቢሲኒያ ባንክ', 'Bank of Abyssinia', '40987654321',
      'ℹ️ የአቢሲኒያ ባንክ አካውንት ቁጥር', 'ℹ️ Bank of Abyssinia Account Number'),
];

class CheckoutScreen extends StatefulWidget {
  /// null = whole cart, otherwise a single cart line index.
  final int? cartIndex;
  const CheckoutScreen({super.key, this.cartIndex});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _selectedMethod = 'telebirr';
  String _region = 'aa';
  XFile? _receipt;
  Uint8List? _receiptBytesPreview;
  bool _submitting = false;
  bool _nameInvalid = false;
  bool _addressInvalid = false;
  bool _receiptInvalid = false;

  // ---- Coin redemption (renderCoinRedemptionBox / handleCoinCheckboxChange) ----
  bool _useCoins = false;
  int _coinsToUse = 0;
  String? _coinPin;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _nameCtrl.text = app.user?.name ?? '';
    _loadPaymentAccounts(app);
  }

  Future<void> _loadPaymentAccounts(AppState app) async {
    final accounts = await app.fetchPaymentAccounts();
    if (accounts == null || !mounted) return;
    setState(() {
      for (final m in _paymentMethods) {
        if (accounts[m.id] != null && accounts[m.id]!.isNotEmpty) m.account = accounts[m.id]!;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final items = widget.cartIndex != null ? [app.cart[widget.cartIndex!]] : app.cart;
    final rawTotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final method = _paymentMethods.firstWhere((m) => m.id == _selectedMethod);

    final discountETB = _useCoins ? WalletService.coinsToEtb(_coinsToUse) : 0.0;
    final total = _useCoins ? WalletService.applyCoinWaiver(rawTotal, discountETB) : rawTotal;
    final receiptRequired = total > 0;
    final eligibility = app.coinRedemptionEligibility(rawTotal);

    return Scaffold(
      appBar: AppBar(title: Text(S.t('checkout_title', lang))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Order summary ----
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('co_summary', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ...items.map((i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(child: Text('${i.name} × ${i.qty}', overflow: TextOverflow.ellipsis)),
                                if (i.color != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: _parseHexColor(i.color!), shape: BoxShape.circle),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(S.formatPrice(i.lineTotal, lang)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Row: name | phone(readonly) ----
          Row(
            children: [
              Expanded(child: _field(S.t('full_name', lang), _nameCtrl, invalid: _nameInvalid, onChanged: (_) => setState(() => _nameInvalid = false))),
              const SizedBox(width: 10),
              Expanded(
                child: _labeled(
                  S.t('phone_number', lang),
                  TextField(
                    controller: TextEditingController(text: app.user?.phone ?? ''),
                    readOnly: true,
                    style: const TextStyle(color: AppTheme.textSecondary),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- Row: payment method | region ----
          Row(
            children: [
              Expanded(
                child: _labeled(
                  S.t('payment_method', lang),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMethod,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(value: m.id, child: Text('${m.emoji} ${m.name(lang)}', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMethod = v ?? _selectedMethod),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _labeled(
                  S.t('region', lang),
                  DropdownButtonFormField<String>(
                    initialValue: _region,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: [
                      DropdownMenuItem(value: 'aa', child: Text(S.t('co_region_aa', lang))),
                      DropdownMenuItem(value: 'dessie', child: Text(S.t('co_region_dessie', lang))),
                      DropdownMenuItem(value: 'kobelcha', child: Text(S.t('co_region_kobelcha', lang))),
                      DropdownMenuItem(value: 'adama', child: Text(S.t('co_region_adama', lang))),
                      DropdownMenuItem(value: 'other', child: Text(S.t('co_region_other', lang))),
                    ],
                    onChanged: (v) => setState(() => _region = v ?? _region),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- Row: address | account number box ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field(S.t('address', lang), _addressCtrl, invalid: _addressInvalid, onChanged: (_) => setState(() => _addressInvalid = false))),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.accountLabel(lang), style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(method.account,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: method.account));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(S.t('co_copy', lang)), duration: const Duration(seconds: 1)));
                            },
                            child: Text(S.t('co_copy', lang),
                                style: const TextStyle(color: AppTheme.brand, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- Row: receipt upload | total ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled(
                  receiptRequired
                      ? '${S.t('receipt_photo', lang)} *'
                      : '${S.t('receipt_photo', lang)} (${S.t('optional', lang)})',
                  GestureDetector(
                    onTap: _pickReceipt,
                    child: Container(
                      height: 110,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: _receiptInvalid ? AppTheme.danger : AppTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _receipt == null
                          ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 30, color: Colors.grey))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_receiptBytesPreview!, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 110,
                  padding: const EdgeInsets.all(10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_useCoins)
                        Text(S.formatPrice(rawTotal, lang),
                            style: const TextStyle(decoration: TextDecoration.lineThrough, fontSize: 12, color: AppTheme.textSecondary)),
                      Text(S.t('co_total', lang), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      Text(S.formatPrice(total, lang),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ---- 🪙 Coin redemption box (renderCoinRedemptionBox) ----
          const SizedBox(height: 14),
          if (app.isAuthenticated && !eligibility.eligible && eligibility.reason == 'balance_too_low')
            _coinNote(lang == 'am'
                ? '🪙 coin መጠቀም የሚቻለው የ coin ቀሪ ሂሳብዎ ከ${S.formatPrice(WalletService.minRedeemEtb, lang)} በላይ ዋጋ ሲኖረው ብቻ ነው። (የእርስዎ ቀሪ፦ ${S.formatNumber(app.coins)} coin ≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)})'
                : "🪙 Coins can only be used once your coin balance is worth more than ${S.formatPrice(WalletService.minRedeemEtb, lang)}. (Your balance: ${S.formatNumber(app.coins)} coins ≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)})")
          else if (app.isAuthenticated && !eligibility.eligible && eligibility.reason == 'no_coins')
            _coinNote(lang == 'am' ? '🪙 በቂ coin የለዎትም።' : "🪙 You don't have enough coins.")
          else if (app.isAuthenticated && eligibility.eligible)
            _CoinToggle(
              lang: lang,
              coins: app.coins,
              maxUsableCoins: eligibility.maxUsableCoins,
              maxDiscount: WalletService.coinsToEtb(eligibility.maxUsableCoins),
              checked: _useCoins,
              onChanged: (checked) async {
                if (checked) {
                  final pin = await _askPin(context, lang);
                  if (pin == null) return; // cancelled
                  setState(() {
                    _useCoins = true;
                    _coinsToUse = eligibility.maxUsableCoins;
                    _coinPin = pin;
                  });
                } else {
                  setState(() {
                    _useCoins = false;
                    _coinsToUse = 0;
                    _coinPin = null;
                  });
                }
              },
            ),

          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _submitting ? null : () => _submit(context, app, rawTotal, total, receiptRequired),
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : Text(S.t('co_complete', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _coinNote(String msg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
        child: Text(msg, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      );

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

  Future<String?> _askPin(BuildContext context, String lang) {
    final ctrl = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(lang == 'am' ? '🔒 ፓስዎርድዎን ያረጋግጡ' : '🔒 Confirm Your Password'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: error,
              hintText: '••••',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(lang == 'am' ? 'ሰርዝ' : 'Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (!RegExp(r'^\d{4}$').hasMatch(v)) {
                  setDialogState(() => error = lang == 'am' ? '4 ቁጥር ያስገቡ' : 'Enter 4 digits');
                  return;
                }
                Navigator.of(dialogContext).pop(v);
              },
              child: Text(lang == 'am' ? 'አረጋግጥ' : 'Confirm'),
            ),
          ],
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
      _receiptBytesPreview = bytes;
      _receiptInvalid = false;
    });
  }

  Future<void> _submit(BuildContext context, AppState app, double rawTotal, double total, bool receiptRequired) async {
    final lang = app.lang;
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    setState(() {
      _nameInvalid = name.isEmpty;
      _addressInvalid = address.isEmpty;
    });
    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('co_fill_fields', lang))));
      return;
    }
    if (receiptRequired && _receipt == null) {
      setState(() => _receiptInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('co_upload_receipt', lang))));
      return;
    }

    setState(() => _submitting = true);

    List<int>? bytes;
    String? filename;
    if (_receipt != null) {
      bytes = await _receipt!.readAsBytes();
      filename = _receipt!.name;
    }

    final method = _paymentMethods.firstWhere((m) => m.id == _selectedMethod);
    final err = await app.placeOrder(
      cartIndex: widget.cartIndex,
      receiptBytes: bytes,
      receiptFilename: filename,
      paymentMethod: _selectedMethod,
      paymentMethodLabel: method.name(lang),
      customerName: name,
      address: address,
      region: _region,
      coinsUsed: _useCoins ? _coinsToUse : 0,
      coinPin: _coinPin,
    );

    setState(() => _submitting = false);
    if (!mounted) return;

    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('order_sent', lang))));
    } else if (err == 'account_blocked') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('account_blocked', lang))));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(lang == 'am' ? '⚠️ ችግር ተፈጥሯል፣ እንደገና ይሞክሩ' : '⚠️ Something went wrong, please try again')));
    }
  }
}

/// Ported from the `.co-coin-toggle-row` block in renderCoinRedemptionBox()
/// (main-coins.js).
class _CoinToggle extends StatelessWidget {
  final String lang;
  final int coins;
  final int maxUsableCoins;
  final double maxDiscount;
  final bool checked;
  final ValueChanged<bool> onChanged;
  const _CoinToggle({
    required this.lang,
    required this.coins,
    required this.maxUsableCoins,
    required this.maxDiscount,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: checked, activeColor: AppTheme.brand, onChanged: (v) => onChanged(v ?? false)),
              Expanded(
                child: Text(
                  lang == 'am'
                      ? '🪙 coin ተጠቀም (የእርስዎ ቀሪ፦ ${S.formatNumber(coins)} coin)'
                      : '🪙 Use Coins (Balance: ${S.formatNumber(coins)} coins)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              lang == 'am'
                  ? 'እስከ ${S.formatNumber(maxUsableCoins)} coin (${S.formatPrice(maxDiscount, lang)}) መጠቀም ይችላሉ — ለማረጋገጫ ፓስዎርድ ይጠየቃሉ'
                  : 'You can use up to ${S.formatNumber(maxUsableCoins)} coins (${S.formatPrice(maxDiscount, lang)}) — Password confirmation required',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

Color _parseHexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return AppTheme.border;
  final value = int.tryParse(h, radix: 16);
  return value == null ? AppTheme.border : Color(value);
}

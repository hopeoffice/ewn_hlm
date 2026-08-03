import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';
import '../widgets/offline_overlay.dart';
import '../widgets/coin_icon.dart';

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
  String? _receiptError;

  // ---- Coin redemption (renderCoinRedemptionBox / handleCoinCheckboxChange) ----
  bool _useCoins = false;
  int _coinsToUse = 0;
  String? _coinPassword;

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
      appBar: AppBar(
        title: Text(S.t('checkout_title', lang)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: S.t('co_help_tooltip', lang),
            onPressed: () => _showCheckoutHelp(context, lang),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Order summary ----
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.tagBg(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: AppTheme.tagText(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('co_summary', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...items.map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name only — allowed to wrap onto a 2nd line
                            // instead of being force-truncated to 1 line,
                            // and kept separate from qty/color/price below
                            // so those can never be eaten by its ellipsis.
                            Expanded(
                              child: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Text('× ${i.qty}'),
                            if (i.color != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(color: _parseHexColor(i.color!), shape: BoxShape.circle),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(S.formatPrice(i.lineTotal, lang)),
                          ],
                        ),
                      )),
                ],
              ),
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
                    style: TextStyle(color: AppTheme.textMuted(context)),
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
                  decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.accountLabel(lang), style: TextStyle(fontSize: 10.5, color: AppTheme.tagText(context).withOpacity(0.75))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(method.account,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.tagText(context)), overflow: TextOverflow.ellipsis),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: method.account));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(S.t('co_copy', lang)), duration: const Duration(seconds: 1)));
                            },
                            child: Text(S.t('co_copy', lang),
                                style: TextStyle(color: AppTheme.tagText(context), fontWeight: FontWeight.bold, fontSize: 12)),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickReceipt,
                        child: Container(
                          height: 110,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: _receiptInvalid ? AppTheme.danger : AppTheme.line(context)),
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
                      if (_receiptError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _receiptError!,
                            style: TextStyle(
                              fontSize: 11,
                              color: _receiptInvalid ? AppTheme.danger : Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 110,
                  padding: const EdgeInsets.all(10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppTheme.goldSoftBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_useCoins)
                        Text(S.formatPrice(rawTotal, lang),
                            style: TextStyle(decoration: TextDecoration.lineThrough, fontSize: 12, color: AppTheme.goldSoftText(context).withOpacity(0.7))),
                      Text(S.t('co_total', lang), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.goldSoftText(context))),
                      Text(S.formatPrice(total, lang),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.goldSoftText(context)), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ---- Coin redemption box (renderCoinRedemptionBox) ----
          const SizedBox(height: 14),
          if (app.isAuthenticated && !eligibility.eligible && eligibility.reason == 'balance_too_low')
            _coinNote(context, lang == 'am'
                ? 'coin መጠቀም የሚቻለው የ coin ቀሪ ሂሳብዎ ከ${S.formatPrice(WalletService.minRedeemEtb, lang)} በላይ ዋጋ ሲኖረው ብቻ ነው። (የእርስዎ ቀሪ፦ ${S.formatNumber(app.coins)} coin ≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)})'
                : "Coins can only be used once your coin balance is worth more than ${S.formatPrice(WalletService.minRedeemEtb, lang)}. (Your balance: ${S.formatNumber(app.coins)} coins ≈ ${S.formatPrice(WalletService.coinsToEtb(app.coins), lang)})")
          else if (app.isAuthenticated && !eligibility.eligible && eligibility.reason == 'no_coins')
            _coinNote(context, lang == 'am' ? 'በቂ coin የለዎትም።' : "You don't have enough coins.")
          else if (app.isAuthenticated && eligibility.eligible)
            _CoinToggle(
              lang: lang,
              coins: app.coins,
              maxUsableCoins: eligibility.maxUsableCoins,
              maxDiscount: WalletService.coinsToEtb(eligibility.maxUsableCoins),
              checked: _useCoins,
              onChanged: (checked) async {
                if (checked) {
                  final password = await _askPassword(context, lang, app);
                  if (password == null) return; // cancelled or wrong password
                  setState(() {
                    _useCoins = true;
                    _coinsToUse = eligibility.maxUsableCoins;
                    _coinPassword = password;
                  });
                } else {
                  setState(() {
                    _useCoins = false;
                    _coinsToUse = 0;
                    _coinPassword = null;
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

  Widget _coinNote(BuildContext context, String msg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CoinIcon(size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: AppTheme.tagText(context)))),
          ],
        ),
      );

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

  /// Ported from openCoinPinModal()/confirmCoinPin() in main-coins.js —
  /// now verifies the password server-side (POST /verifyPassword)
  /// immediately, instead of only checking the 4-digit format locally
  /// and deferring the real check to final checkout submission.
  Future<String?> _askPassword(BuildContext context, String lang, AppState app) {
    final ctrl = TextEditingController();
    String? error;
    bool checking = false;
    return showDialog<String>(
      context: context,
      barrierDismissible: !checking,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(lang == 'am' ? '🔒 ፓስዎርድዎን ያረጋግጡ' : '🔒 Confirm Your Password'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            autofocus: true,
            enabled: !checking,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: error,
              hintText: '••••',
            ),
          ),
          actions: [
            TextButton(
              onPressed: checking ? null : () => Navigator.of(dialogContext).pop(),
              child: Text(lang == 'am' ? 'ሰርዝ' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: checking
                  ? null
                  : () async {
                      final v = ctrl.text.trim();
                      if (!RegExp(r'^\d{4}$').hasMatch(v)) {
                        setDialogState(() => error = lang == 'am' ? '4 ቁጥር ያስገቡ' : 'Enter 4 digits');
                        return;
                      }
                      if (!await requireOnlineOrWarn(dialogContext, lang)) return;
                      setDialogState(() {
                        checking = true;
                        error = null;
                      });
                      final err = await app.verifyPassword(v);
                      if (err == null) {
                        if (dialogContext.mounted) Navigator.of(dialogContext).pop(v);
                      } else {
                        setDialogState(() {
                          checking = false;
                          error = err == 'locked_try_later'
                              ? (lang == 'am' ? '⚠️ ብዙ ጊዜ ተሳስተዋል፣ ቆይተው ይሞክሩ' : '⚠️ Too many attempts, try later')
                              : (lang == 'am' ? '❌ የተሳሳተ ፓስዎርድ' : '❌ Incorrect password');
                        });
                      }
                    },
              child: checking
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(lang == 'am' ? 'አረጋግጥ' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  /// Ported from handleReceiptUpload() in main-actions.js — validates the
  /// picked file is an image and under 1MB, same as the web app. Was
  /// previously entirely missing: any file the gallery picker returned
  /// was accepted as-is, with no size/type feedback to the person if
  /// something oversized or wrong got through.
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
        _receiptBytesPreview = null;
        _receiptInvalid = true;
        _receiptError = S.t('co_receipt_type', lang);
      });
      return;
    }

    final bytes = await picked.readAsBytes();
    if (bytes.length > 1024 * 1024) {
      setState(() {
        _receipt = null;
        _receiptBytesPreview = null;
        _receiptInvalid = true;
        _receiptError = S.t('co_receipt_large', lang);
      });
      return;
    }

    setState(() {
      _receipt = picked;
      _receiptBytesPreview = bytes;
      _receiptInvalid = false;
      _receiptError = S.t('co_receipt_valid', lang);
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
    if (!await requireOnlineOrWarn(context, lang)) return;
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
      coinPassword: _coinPassword,
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

  /// Ported from openCheckoutHelp()/closeCheckoutHelp() in main-actions.js
  /// — the "?" button on the checkout screen that shows a bilingual
  /// 6-step "how to order" guide plus technical-support contact info.
  void _showCheckoutHelp(BuildContext context, String lang) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.t('co_help_title', lang),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (int i = 1; i <= 6; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
                          child: Text('$i', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(S.t('co_help_step$i', lang), style: const TextStyle(fontSize: 13.5))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: AppTheme.tagText(context)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.t('co_help_support_title', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(S.t('co_help_support_hc', lang), style: const TextStyle(fontSize: 12.5)),
                        Text(S.t('co_help_support_email', lang), style: const TextStyle(fontSize: 12.5)),
                        Text(S.t('co_help_support_phone', lang), style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: checked, activeColor: AppTheme.brand, onChanged: (v) => onChanged(v ?? false)),
              const CoinIcon(size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  lang == 'am'
                      ? 'coin ተጠቀም (የእርስዎ ቀሪ፦ ${S.formatNumber(coins)} coin)'
                      : 'Use Coins (Balance: ${S.formatNumber(coins)} coins)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.tagText(context)),
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
              style: TextStyle(fontSize: 11.5, color: AppTheme.tagText(context).withOpacity(0.8)),
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

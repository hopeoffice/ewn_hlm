import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Ported from PAYMENT_METHODS in main-actions.js. In production, load
/// account numbers from Realtime DB (settings/paymentAccounts) instead
/// of hardcoding — see loadPaymentAccountsFromDb() in the original app.
class _PaymentMethod {
  final String id;
  final String emoji;
  final String nameAm;
  final String account;
  const _PaymentMethod(this.id, this.emoji, this.nameAm, this.account);
}

const _paymentMethods = [
  _PaymentMethod('telebirr', '📱', 'ቴሌብር', '0932208224'),
  _PaymentMethod('cbe', '🏦', 'ንግድ ባንክ (CBE)', '1000123456789'),
  _PaymentMethod('abyssinia', '🏦', 'አቢሲኒያ ባንክ', '40987654321'),
];

class CheckoutScreen extends StatefulWidget {
  /// null = whole cart, otherwise a single cart line index.
  final int? cartIndex;
  const CheckoutScreen({super.key, this.cartIndex});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedMethod = 'telebirr';
  XFile? _receipt;
  bool _submitting = false;
  bool _useCoinsOnly = false; // when true, no receipt is required

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = widget.cartIndex != null ? [app.cart[widget.cartIndex!]] : app.cart;
    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final method = _paymentMethods.firstWhere((m) => m.id == _selectedMethod);

    return Scaffold(
      appBar: AppBar(title: const Text('ትዕዛዝ ያጠናቅቁ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.map((i) => Text('${i.name} x${i.qty} — ${i.lineTotal.toStringAsFixed(0)} ብር')),
                  const Divider(),
                  Text('ጠቅላላ: ${total.toStringAsFixed(0)} ብር',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('የክፍያ ዘዴ ይምረጡ', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._paymentMethods.map(
            (m) => RadioListTile<String>(
              value: m.id,
              groupValue: _selectedMethod,
              activeColor: AppTheme.brand,
              title: Text('${m.emoji} ${m.nameAm}'),
              onChanged: (v) => setState(() => _selectedMethod = v!),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppTheme.brand),
                const SizedBox(width: 8),
                Expanded(child: Text('${method.nameAm} አካውንት ቁጥር: ${method.account}')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            value: _useCoinsOnly,
            activeColor: AppTheme.brand,
            title: const Text('🪙 ሙሉ በሙሉ በ Coin ብቻ ክፈል (ደረሰኝ አያስፈልግም)'),
            onChanged: (v) => setState(() => _useCoinsOnly = v),
          ),
          if (!_useCoinsOnly) ...[
            const SizedBox(height: 8),
            const Text('የክፍያ ደረሰኝ ስክሪንሾት ያያይዙ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickReceipt,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _receipt == null
                    ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.grey))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_receiptBytesPreview!, fit: BoxFit.cover),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : const Text('ትዕዛዝ ላክ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Uint8List? _receiptBytesPreview;

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _receipt = picked;
      _receiptBytesPreview = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_useCoinsOnly && _receipt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('እባክዎ የክፍያ ደረሰኝ ያያይዙ')));
      return;
    }
    setState(() => _submitting = true);

    final app = context.read<AppState>();
    List<int>? bytes;
    String? filename;
    if (!_useCoinsOnly && _receipt != null) {
      bytes = await _receipt!.readAsBytes();
      filename = _receipt!.name;
    }

    final err = await app.placeOrder(
      cartIndex: widget.cartIndex,
      receiptBytes: bytes,
      receiptFilename: filename,
      paymentMethod: _useCoinsOnly ? 'coins' : _selectedMethod,
    );

    setState(() => _submitting = false);
    if (!mounted) return;

    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ ትዕዛዝዎ ተልኳል')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ ችግር ተፈጥሯል፣ እንደገና ይሞክሩ')));
    }
  }
}

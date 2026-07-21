import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Same two-step flow as the "እንኳን ደህና መጡ" modal group in index.html:
/// phone number -> PIN (login), with a link to switch to registration.
Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AuthSheet(),
  );
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  bool isRegister = false;
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final err = isRegister
        ? await app.register(_nameCtrl.text.trim(), _phoneCtrl.text.trim(), _pinCtrl.text.trim(),
            incomingReferralCode: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim())
        : await app.login(_phoneCtrl.text.trim(), _pinCtrl.text.trim());
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  String _errorText(String code) {
    switch (code) {
      case 'user_not_found':
        return 'ተጠቃሚ አልተገኘም';
      case 'wrong_pin':
        return 'የተሳሳተ ፓስዎርድ';
      case 'already_registered':
        return 'ይህ ስልክ ቁጥር ቀድሞ ተመዝግቧል';
      default:
        return 'ችግር ተፈጥሯል፣ እንደገና ይሞክሩ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isRegister ? 'አዲስ መለያ ይክፈቱ' : 'እንኳን ደህና መጡ',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (isRegister)
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'ሙሉ ስም', border: OutlineInputBorder()),
            ),
          if (isRegister) const SizedBox(height: 12),
          if (isRegister)
            TextField(
              controller: _refCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'የግብዣ ኮድ (ካለ) — Referral Code',
                border: OutlineInputBorder(),
              ),
            ),
          if (isRegister) const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'ስልክ ቁጥር', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'ፓስዎርድ (4 ቁጥር)', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : Text(isRegister ? 'ይመዝገቡ' : 'ግባ', style: const TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => setState(() => isRegister = !isRegister),
            child: Text(isRegister ? 'ወደ መግቢያ ተመለስ' : 'አዲስ መለያ ይክፈቱ'),
          ),
        ],
      ),
    );
  }
}

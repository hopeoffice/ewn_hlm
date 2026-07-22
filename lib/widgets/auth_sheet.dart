import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Ported from the "እንኳን ደህና መጡ" modal group in index.html — a real
/// multi-step flow, NOT a single form with a login/register toggle:
///   1) Phone number → look up users/{phone}
///   2a) Exists  → Login step (welcome name + PIN + "ፓስዎርድ ረሳሁ?")
///   2b) New     → Register step (name, PIN, PIN confirm, security
///                 question + answer, optional referral code)
///   3) Forgot-PIN step, reached from the login step.
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

enum _AuthStep { phone, login, register, forgot }

/// Ported from the qKey map in showForgotPin() (main-config.js) — the 7
/// fixed recovery-question choices, same keys stored in
/// users/{phone}/securityQuestion.
const Map<String, String> kSecurityQuestions = {
  'dob': 'የትውልድ ዓ.ም',
  'pob': 'የትውልድ ቦታ',
  'mother': 'የእናት ስም',
  'pet': 'የቤት እንስሳዎ ስም',
  'school': 'የመጀመሪያ ደረጃ ትምህርት ቤትዎ ስም',
  'color': 'የሚወዱት ቀለም',
  'friend': 'የቅርብ ጓደኛዎ ስም',
};

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  _AuthStep step = _AuthStep.phone;

  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _forgotAnswerCtrl = TextEditingController();
  final _forgotNewPinCtrl = TextEditingController();
  String _securityQuestion = kSecurityQuestions.keys.first;

  Map<String, dynamic>? _lookedUpUser; // set once the phone step resolves
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    _nameCtrl.dispose();
    _refCtrl.dispose();
    _answerCtrl.dispose();
    _forgotAnswerCtrl.dispose();
    _forgotNewPinCtrl.dispose();
    super.dispose();
  }

  // ---------------- Step 1: phone lookup ----------------

  Future<void> _submitPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (!AppState.ethioPhoneRe.hasMatch(phone)) {
      setState(() => _error = '❌ ትክክለኛ ስልክ ቁጥር ያስገቡ (09xxxxxxxx ወይም 07xxxxxxxx)');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await context.read<AppState>().checkPhone(phone);
    setState(() {
      _loading = false;
      _lookedUpUser = data;
      step = data != null ? _AuthStep.login : _AuthStep.register;
    });
  }

  // ---------------- Step 2a: login ----------------

  Future<void> _submitLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().login(_phoneCtrl.text.trim(), _pinCtrl.text.trim());
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  // ---------------- Step 2b: register ----------------

  Future<void> _submitRegister() async {
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final pin2 = _pin2Ctrl.text.trim();
    final answer = _answerCtrl.text.trim();

    if (name.isEmpty || answer.isEmpty || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = !RegExp(r'^\d{4}$').hasMatch(pin) ? '❌ ፓስዎርድ 4 ቁጥር መሆን አለበት' : '⚠️ ሁሉንም መስኮች ይሙሉ');
      return;
    }
    if (pin != pin2) {
      setState(() => _error = '❌ ፓስዎርዶቹ አይመሳሰሉም');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().register(
          name,
          _phoneCtrl.text.trim(),
          pin,
          securityQuestion: _securityQuestion,
          securityAnswer: answer,
          incomingReferralCode: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        );
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  // ---------------- Step 3: forgot PIN ----------------

  void _goToForgotPin() {
    setState(() {
      _error = null;
      step = _AuthStep.forgot;
    });
  }

  Future<void> _submitForgotPin() async {
    final answer = _forgotAnswerCtrl.text.trim();
    final newPin = _forgotNewPinCtrl.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
      setState(() => _error = '❌ ፓስዎርድ 4 ቁጥር መሆን አለበት');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().resetPin(_phoneCtrl.text.trim(), answer, newPin);
    setState(() => _loading = false);
    if (err == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ ፓስዎርድዎ ተቀይሯል!')));
      setState(() {
        step = _AuthStep.login;
        _pinCtrl.clear();
      });
    } else {
      setState(() => _error = err == 'wrong_answer' ? '❌ መልሱ ትክክል አይደለም' : _errorText(err));
    }
  }

  String _errorText(String code) {
    switch (code) {
      case 'user_not_found':
        return 'ተጠቃሚ አልተገኘም';
      case 'wrong_pin':
        return 'የተሳሳተ ፓስዎርድ';
      case 'account_blocked':
        return '⛔ ይህ አካውንት ታግዷል';
      case 'already_registered':
        return 'ይህ ስልክ ቁጥር ቀድሞ ተመዝግቧል';
      case 'locked_try_later':
        return '⛔ ብዙ ጊዜ ተሞክሯል፣ ቆይተው ይሞክሩ';
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
          if (step != _AuthStep.phone)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _error = null;
                  step = step == _AuthStep.forgot ? _AuthStep.login : _AuthStep.phone;
                }),
              ),
            ),
          ..._buildStep(),
        ],
      ),
    );
  }

  List<Widget> _buildStep() {
    switch (step) {
      case _AuthStep.phone:
        return _phoneStep();
      case _AuthStep.login:
        return _loginStep();
      case _AuthStep.register:
        return _registerStep();
      case _AuthStep.forgot:
        return _forgotStep();
    }
  }

  List<Widget> _phoneStep() => [
        const Text('እንኳን ደህና መጡ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'ስልክ ቁጥር (09xxxxxxxx)', border: OutlineInputBorder()),
        ),
        if (_error != null) _errorLine(),
        const SizedBox(height: 12),
        _submitButton(_loading ? null : _submitPhone, 'ቀጥል'),
      ];

  List<Widget> _loginStep() => [
        Text('እንኳን ደህና መጡ ${_lookedUpUser?['name'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'ፓስዎርድ (4 ቁጥር)', border: OutlineInputBorder()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _goToForgotPin, child: const Text('ፓስዎርድ ረሳሁ?')),
        ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitLogin, 'ግባ'),
      ];

  List<Widget> _registerStep() => [
        const Text('አዲስ መለያ ይክፈቱ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'ሙሉ ስም', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'ፓስዎርድ (4 ቁጥር)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin2Ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'ፓስዎርድ ያረጋግጡ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _securityQuestion,
          decoration: const InputDecoration(
            labelText: 'የመልሶ ማግኛ ጥያቄ (ፓስዎርድ ቢረሱ)',
            border: OutlineInputBorder(),
          ),
          items: kSecurityQuestions.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _securityQuestion = v ?? _securityQuestion),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _answerCtrl,
          decoration: const InputDecoration(labelText: 'መልስ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _refCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'የግብዣ ኮድ (ካለ) — Referral Code',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitRegister, 'ይመዝገቡ'),
      ];

  List<Widget> _forgotStep() {
    final qKey = _lookedUpUser?['securityQuestion'] as String? ?? 'dob';
    final question = kSecurityQuestions[qKey] ?? kSecurityQuestions['dob']!;
    return [
      const Text('ፓስዎርድ ይቀየር', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(question, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      TextField(
        controller: _forgotAnswerCtrl,
        decoration: const InputDecoration(labelText: 'መልስ', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _forgotNewPinCtrl,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'አዲስ ፓስዎርድ (4 ቁጥር)', border: OutlineInputBorder()),
      ),
      if (_error != null) _errorLine(),
      _submitButton(_loading ? null : _submitForgotPin, 'ፓስዎርድ ይቀይሩ'),
    ];
  }

  Widget _errorLine() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
      );

  Widget _submitButton(VoidCallback? onPressed, String label) => ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: onPressed,
        child: _loading
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
            : Text(label, style: const TextStyle(color: Colors.white)),
      );
}

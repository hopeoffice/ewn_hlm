import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'offline_overlay.dart';

/// Ported from the "እንኳን ደህና መጡ" modal group in index.html — a real
/// multi-step flow, NOT a single form with a login/register toggle:
///   1) Phone number → look up users/{phone}
///   2a) Exists + emailVerified  → Login step (welcome name + password +
///       "ፓስዎርድ ረሳሁ?")
///   2b) Exists + NOT emailVerified → Migrate step (legacy PIN-only
///       account: must add email + set a new password before it can be
///       used again)
///   2c) New → Register step (name, email, password, password confirm,
///       optional referral code)
///   3) Verify step (shared by register + migrate): 5-digit email code,
///      with a resend button + 2-minute cooldown timer.
///   4) Forgot-password step, reached from the login step: email (with a
///      masked hint of the real one) → 5-digit code + new password in
///      one combined submit.
///
/// BUGFIX: was `showModalBottomSheet(...)` — a partial-height sheet. The
/// web app's login/register flow (`#auth-overlay`) is a full-screen
/// overlay that covers the entire viewport, not a bottom sheet, so this
/// is pushed as a full-screen route to match (and to be consistent with
/// checkout/product detail, which are also full screens).
Future<void> showAuthSheet(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const _AuthSheet(), fullscreenDialog: true),
  );
}

enum _AuthStep { phone, login, migrate, register, verify, forgot }

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _passwordRe = RegExp(r'^\d{4}$');

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  _AuthStep step = _AuthStep.phone;

  final _phoneCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  final _migrateEmailCtrl = TextEditingController();
  final _migratePasswordCtrl = TextEditingController();
  final _migratePassword2Ctrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regPassword2Ctrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _verifyCodeCtrl = TextEditingController();
  final _forgotEmailCtrl = TextEditingController();
  final _resetCodeCtrl = TextEditingController();
  final _resetPasswordCtrl = TextEditingController();

  Map<String, dynamic>? _lookedUpUser; // set once the phone step resolves
  String _verifyPurpose = 'register'; // 'register' | 'migrate'
  String? _error;
  bool _loading = false;
  bool _forgotSent = false;
  int _resendSeconds = 0;
  // ✅ FIX: ports setCodeTimerBlocked() in main-config.js. When the
  // Worker returns error 'blocked' (resend rate-limit hit), the web app
  // permanently disables the resend/send button for the rest of this
  // modal session (not just a 120s cooldown) and shows a distinct
  // "resend limit reached" message. Previously this Flutter port only
  // showed the error text once while leaving the button tappable again
  // immediately, letting the user keep hammering resend during a block.
  bool _resendBlocked = false;
  bool _privacyConsent = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _migrateEmailCtrl.dispose();
    _migratePasswordCtrl.dispose();
    _migratePassword2Ctrl.dispose();
    _nameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regPassword2Ctrl.dispose();
    _refCtrl.dispose();
    _verifyCodeCtrl.dispose();
    _forgotEmailCtrl.dispose();
    _resetCodeCtrl.dispose();
    _resetPasswordCtrl.dispose();
    super.dispose();
  }

  String get _lang => context.read<AppState>().lang;

  void _startResendTimer() {
    _resendBlocked = false;
    _resendSeconds = 120;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendSeconds = _resendSeconds > 0 ? _resendSeconds - 1 : 0);
      return _resendSeconds > 0;
    });
  }

  // ---------------- Step 1: phone lookup ----------------

  Future<void> _submitPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (!AppState.ethioPhoneRe.hasMatch(phone)) {
      setState(() => _error = S.t('auth_invalid_phone', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await context.read<AppState>().checkPhone(phone);
    setState(() {
      _loading = false;
      _lookedUpUser = data;
      if (data == null) {
        step = _AuthStep.register;
      } else if (data['emailVerified'] == true) {
        _loginPasswordCtrl.clear();
        step = _AuthStep.login;
      } else {
        step = _AuthStep.migrate;
      }
    });
  }

  // ---------------- Step 2a: login ----------------

  Future<void> _submitLogin() async {
    final password = _loginPasswordCtrl.text.trim();
    if (password.length < 4) {
      setState(() => _error = S.t('invalid_password', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().login(_phoneCtrl.text.trim(), password);
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) Navigator.pop(context);
    } else if (err == 'migration_required') {
      setState(() {
        _error = null;
        step = _AuthStep.migrate;
      });
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  void _goToForgotPin() {
    setState(() {
      _error = null;
      _forgotSent = false;
      _resendBlocked = false;
      _forgotEmailCtrl.clear();
      _resetCodeCtrl.clear();
      _resetPasswordCtrl.clear();
      step = _AuthStep.forgot;
    });
  }

  // ---------------- Step 2b: migrate (legacy PIN-only accounts) ----------------

  Future<void> _submitMigrateStart() async {
    final email = _migrateEmailCtrl.text.trim();
    final password = _migratePasswordCtrl.text.trim();
    final password2 = _migratePassword2Ctrl.text.trim();

    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = S.t('invalid_email', _lang));
      return;
    }
    if (!_passwordRe.hasMatch(password)) {
      setState(() => _error = S.t('invalid_password', _lang));
      return;
    }
    if (password != password2) {
      setState(() => _error = S.t('pin_mismatch', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().startMigrate(phone: _phoneCtrl.text.trim(), email: email, password: password);
    setState(() => _loading = false);
    if (err == null) {
      _verifyPurpose = 'migrate';
      _verifyCodeCtrl.clear();
      _startResendTimer();
      setState(() => step = _AuthStep.verify);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  // ---------------- Step 2c: register ----------------

  Future<void> _submitRegisterStart() async {
    final name = _nameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPasswordCtrl.text.trim();
    final password2 = _regPassword2Ctrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = S.t('fill_all_fields', _lang));
      return;
    }
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = S.t('invalid_email', _lang));
      return;
    }
    if (!_passwordRe.hasMatch(password)) {
      setState(() => _error = S.t('invalid_password', _lang));
      return;
    }
    if (password != password2) {
      setState(() => _error = S.t('pin_mismatch', _lang));
      return;
    }
    if (!_privacyConsent) {
      setState(() => _error = S.t('privacy_consent_required', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().startRegister(
          name: name,
          phone: _phoneCtrl.text.trim(),
          email: email,
          password: password,
          incomingReferralCode: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        );
    setState(() => _loading = false);
    if (err == null) {
      _verifyPurpose = 'register';
      _verifyCodeCtrl.clear();
      _startResendTimer();
      setState(() => step = _AuthStep.verify);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  // ---------------- Step 3: verify (shared: register / migrate) ----------------

  Future<void> _submitVerifyCode() async {
    final code = _verifyCodeCtrl.text.trim();
    if (code.length < 5) {
      setState(() => _error = S.t('wrong_code', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final err = _verifyPurpose == 'register' ? await app.completeRegister(code) : await app.completeMigrate(code);
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  Future<void> _resendVerifyCode() async {
    if (_resendSeconds > 0 || _resendBlocked) return;
    if (!await requireOnlineOrWarn(context, _lang)) return;
    final app = context.read<AppState>();
    final err = _verifyPurpose == 'register' ? await app.resendRegisterCode() : await app.resendMigrateCode();
    if (err == null) {
      _startResendTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('code_sent', _lang))));
      }
    } else if (mounted) {
      // ✅ FIX (see _resendBlocked doc comment): 'blocked' permanently
      // disables the button for this session instead of a 120s cooldown.
      setState(() {
        _error = _errorText(err);
        if (err == 'blocked') _resendBlocked = true;
      });
    }
  }

  // ---------------- Step 4: forgot password ----------------

  Future<void> _sendForgotCode() async {
    final email = _forgotEmailCtrl.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = S.t('invalid_email', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().sendForgotCode(phone: _phoneCtrl.text.trim(), email: email);
    setState(() => _loading = false);
    if (err == null) {
      _forgotSent = true;
      _startResendTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('code_sent', _lang))));
      setState(() {});
    } else if (err == 'migration_required') {
      setState(() {
        _error = null;
        step = _AuthStep.migrate;
      });
    } else {
      // ✅ FIX (see _resendBlocked doc comment): 'blocked' permanently
      // disables the "send code" button for this session.
      setState(() {
        _error = _errorText(err);
        if (err == 'blocked') _resendBlocked = true;
      });
    }
  }

  Future<void> _submitForgotReset() async {
    final code = _resetCodeCtrl.text.trim();
    final newPassword = _resetPasswordCtrl.text.trim();
    if (code.length < 5) {
      setState(() => _error = S.t('wrong_code', _lang));
      return;
    }
    if (!_passwordRe.hasMatch(newPassword)) {
      setState(() => _error = S.t('invalid_password', _lang));
      return;
    }
    if (!await requireOnlineOrWarn(context, _lang)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AppState>().completeForgotPassword(
          phone: _phoneCtrl.text.trim(),
          code: code,
          newPassword: newPassword,
        );
    setState(() => _loading = false);
    if (err == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('pin_reset_success', _lang))));
        Navigator.pop(context);
      }
    } else {
      setState(() => _error = _errorText(err));
    }
  }

  /// Ported from goToLoginStep() in main-config.js — goes back to the
  /// password-login step without re-asking for the phone number.
  void _goToLoginStep() {
    setState(() {
      _error = null;
      if (_lookedUpUser != null && _lookedUpUser!['emailVerified'] == true) {
        _loginPasswordCtrl.clear();
        step = _AuthStep.login;
      } else {
        step = _AuthStep.phone;
      }
    });
  }

  String _errorText(String code) {
    final lang = _lang;
    switch (code) {
      case 'user_not_found':
        return S.t('user_not_found', lang);
      case 'wrong_password':
        return S.t('wrong_password', lang);
      case 'account_blocked':
        return S.t('account_blocked', lang);
      case 'locked_try_later':
        return S.t('too_many_attempts', lang);
      case 'already_registered':
        return S.t('already_registered', lang);
      case 'invalid_email':
        return S.t('invalid_email', lang);
      case 'email_mismatch':
        return S.t('email_mismatch', lang);
      case 'invalid_input':
      case 'invalid_password':
        return S.t('invalid_password', lang);
      case 'code_expired':
        return S.t('code_expired', lang);
      case 'wrong_code':
        return S.t('wrong_code', lang);
      case 'cooldown':
        return S.t('resend_wait', lang);
      case 'blocked':
        return S.t('resend_limit_reached', lang);
      default:
        return S.t('connection_error', lang);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(step == _AuthStep.phone ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (step == _AuthStep.phone) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _error = null;
                step = _AuthStep.phone;
              });
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildStep(context.watch<AppState>().lang),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(String lang) {
    switch (step) {
      case _AuthStep.phone:
        return _phoneStep(lang);
      case _AuthStep.login:
        return _loginStep(lang);
      case _AuthStep.migrate:
        return _migrateStep(lang);
      case _AuthStep.register:
        return _registerStep(lang);
      case _AuthStep.verify:
        return _verifyStep(lang);
      case _AuthStep.forgot:
        return _forgotStep(lang);
    }
  }

  List<Widget> _phoneStep(String lang) => [
        Text(S.t('login_title', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: S.t('phone_number', lang), border: const OutlineInputBorder()),
        ),
        if (_error != null) _errorLine(),
        const SizedBox(height: 12),
        _submitButton(_loading ? null : _submitPhone, S.t('continue_btn', lang)),
      ];

  List<Widget> _loginStep(String lang) => [
        Text('${S.t('login_title', lang)} ${_lookedUpUser?['name'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(S.t('login_sub_pin', lang), style: TextStyle(color: AppTheme.textMuted(context))),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(labelText: S.t('pin_code', lang), border: const OutlineInputBorder()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _goToForgotPin, child: Text(S.t('forgot_pin', lang))),
        ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitLogin, S.t('login_btn_pin', lang)),
      ];

  List<Widget> _migrateStep(String lang) => [
        Text(S.t('migrate_title', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(S.t('migrate_sub', lang), style: TextStyle(color: AppTheme.textMuted(context))),
        const SizedBox(height: 16),
        TextField(
          controller: _migrateEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: S.t('email_address', lang), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _migratePasswordCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(labelText: S.t('pin_code', lang), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _migratePassword2Ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(labelText: S.t('pin_confirm', lang), border: const OutlineInputBorder()),
        ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitMigrateStart, S.t('continue_btn', lang)),
      ];

  List<Widget> _registerStep(String lang) => [
        Text(S.t('register_title', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
              labelText: S.t('full_name', lang),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
              labelText: S.t('email_address', lang),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(
              labelText: S.t('pin_code', lang),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPassword2Ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(
              labelText: S.t('pin_confirm', lang),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _refCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
              labelText: S.t('promo_code_label', lang),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => setState(() => _privacyConsent = !_privacyConsent),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _privacyConsent,
                  onChanged: (v) => setState(() => _privacyConsent = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Wrap(
                    children: [
                      Text(lang == 'am' ? 'የ' : 'I have read and agree to the ', style: const TextStyle(fontSize: 13)),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse(WalletService.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                        child: Text(
                          lang == 'am' ? 'ፕራይቬሲ ፖሊሲ' : 'Privacy Policy',
                          style: const TextStyle(fontSize: 13, color: AppTheme.brand, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                        ),
                      ),
                      Text(lang == 'am' ? 'ን አንብቤ ተስማምቻለሁ' : '', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitRegisterStart, S.t('register_btn', lang)),
      ];

  List<Widget> _verifyStep(String lang) => [
        Text(S.t('enter_code_title', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          (lang == 'am' ? 'ኮድ ወደ ' : 'A code was sent to ') +
              (_verifyPurpose == 'register' ? _regEmailCtrl.text.trim() : _migrateEmailCtrl.text.trim()),
          style: TextStyle(color: AppTheme.textMuted(context)),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _verifyCodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: InputDecoration(
                    hintText: S.t('enter_code_placeholder', lang), border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_resendSeconds > 0 || _resendBlocked) ? null : _resendVerifyCode,
              child: Text(S.t('send_code_btn', lang)),
            ),
          ],
        ),
        if (_resendBlocked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              S.t('resend_limit_reached', lang),
              style: const TextStyle(fontSize: 12, color: AppTheme.danger),
            ),
          )
        else if (_resendSeconds > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              lang == 'am' ? 'ድጋሚ ላክ በ ${_resendSeconds}ሰ' : 'Resend in ${_resendSeconds}s',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
            ),
          ),
        if (_error != null) _errorLine(),
        _submitButton(_loading ? null : _submitVerifyCode, S.t('confirm_code_btn', lang)),
      ];

  List<Widget> _forgotStep(String lang) {
    final hint = _lookedUpUser?['email'] != null ? _maskEmail(_lookedUpUser!['email'] as String) : null;
    return [
      Text(S.t('forgot_pin_title', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(
        hint != null
            ? '${S.t('forgot_sub_email', lang)} (${lang == 'am' ? 'ፍንጭ፦ ' : 'hint: '}$hint)'
            : S.t('forgot_sub_email', lang),
        style: TextStyle(color: AppTheme.textMuted(context)),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _forgotEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: S.t('email_address', lang), border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: (_forgotEmailCtrl.text.trim().isEmpty || _resendSeconds > 0 || _resendBlocked)
                ? null
                : _sendForgotCode,
            child: Text(S.t('send_code_btn', lang)),
          ),
        ],
      ),
      if (_resendBlocked)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            S.t('resend_limit_reached', lang),
            style: const TextStyle(fontSize: 12, color: AppTheme.danger),
          ),
        )
      else if (_resendSeconds > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            lang == 'am' ? 'ድጋሚ ላክ በ ${_resendSeconds}ሰ' : 'Resend in ${_resendSeconds}s',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
          ),
        ),
      if (_forgotSent) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _resetCodeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 5,
          decoration: InputDecoration(labelText: S.t('enter_code_title', lang), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _resetPasswordCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: InputDecoration(labelText: S.t('new_pin', lang), border: const OutlineInputBorder()),
        ),
      ],
      if (_error != null) _errorLine(),
      const SizedBox(height: 8),
      _submitButton(_loading || !_forgotSent ? null : _submitForgotReset, S.t('reset_pin_btn', lang)),
      Align(
        alignment: Alignment.center,
        child: TextButton(onPressed: _goToLoginStep, child: Text(S.t('try_password_link', lang))),
      ),
    ];
  }

  /// Ported from maskEmailClient() in main-config.js.
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts[0].isEmpty) return '';
    final user = parts[0];
    final domain = parts[1];
    if (user.length <= 5) return '${user[0]}***@$domain';
    return '${user.substring(0, 3)}****${user.substring(user.length - 2)}@$domain';
  }

  Widget _errorLine() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
      );

  Widget _submitButton(VoidCallback? onPressed, String label) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: onPressed,
          child: _loading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
              : Text(label, style: const TextStyle(color: Colors.white)),
        ),
      );
}

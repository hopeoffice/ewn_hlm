import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/password_field.dart';
import 'wallet_screen.dart' show promptWalletPassword; // reuse the shared password-confirm dialog

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _passwordRe = RegExp(r'^\d{4}$');
const int _wizardTotalSteps = 2;

/// Ported from maskEmailClient() in main-config.js.
String _maskEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return '';
  final user = parts[0];
  final domain = parts[1];
  if (user.length <= 5) return '${user[0]}***@$domain';
  return '${user.substring(0, 3)}****${user.substring(user.length - 2)}@$domain';
}

String _formatDate(int ms, String lang) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Doubles as the "Wallet Activation" wizard for basic-tier (phone-only)
/// accounts — reached directly when tapping "የኔ ዋሌት" (My Wallet) from the
/// profile menu. A basic-tier account has no name yet (registration is
/// phone-only), so this 5-step wizard collects name → promo code →
/// email → password → email-code confirmation, all together, and only
/// touches the server once everything is validated (step 4 → 5).
/// Wallet-tier accounts see the original read-only email/phone +
/// editable (password-gated) name view, unchanged.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late Future<Map<String, dynamic>?> _userFuture;

  // ---- Wallet-tier: name change ----
  final _nameCtrl = TextEditingController();
  bool _submittingName = false;

  // ---- Basic-tier: 5-step wallet-activation wizard ----
  int _wizardStep = 1;
  final _wizardNameCtrl = TextEditingController();
  final _wizardPromoCtrl = TextEditingController();
  final _wizardEmailCtrl = TextEditingController();
  final _wizardPasswordCtrl = TextEditingController();
  final _wizardPassword2Ctrl = TextEditingController();
  final _wizardCodeCtrl = TextEditingController();
  bool _wizardLoading = false;
  String? _wizardError;
  bool _codeSent = false;
  int _resendSeconds = 0;
  bool _resendBlocked = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _nameCtrl.text = app.user?.name ?? '';
    _userFuture = app.checkPhone(app.user!.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wizardNameCtrl.dispose();
    _wizardPromoCtrl.dispose();
    _wizardEmailCtrl.dispose();
    _wizardPasswordCtrl.dispose();
    _wizardPassword2Ctrl.dispose();
    _wizardCodeCtrl.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';
    final isBasic = !app.isWalletActivated;

    return Scaffold(
      appBar: AppBar(title: Text('👤 ${S.t('edit_profile_menu', lang)}')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _userFuture,
        builder: (context, snap) {
          // BUGFIX: `snap.hasData` is `data != null` — for a brand-new
          // phone (lazy account creation means checkPhone() correctly
          // returns null, since no users/{phone} record exists yet),
          // that stayed false FOREVER even after the future resolved,
          // so the wizard never rendered — just an infinite spinner.
          // Checking connectionState instead distinguishes "still
          // waiting" from "loaded, and the result happens to be null".
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final u = snap.data ?? {};

          if (isBasic) {
            return _buildWizard(context, app, lang, isAm);
          }
          return _buildWalletTierView(context, app, u, lang, isAm);
        },
      ),
    );
  }

  // ================================================================
  //  WALLET-TIER VIEW — unchanged: editable (password-gated) name,
  //  read-only email + phone.
  // ================================================================

  Widget _buildWalletTierView(
      BuildContext context, AppState app, Map<String, dynamic> u, String lang, bool isAm) {
    final email = (u['email'] as String?) ?? '';
    final maskedEmail = email.isNotEmpty ? _maskEmail(email) : (isAm ? 'አልገባም' : 'Not set');
    final nameChangedAt = (u['nameChangedAt'] as num?)?.toInt();
    final nextAllowedAt = nameChangedAt != null ? nameChangedAt + WalletService.nameChangeCooldownMs : 0;
    final onCooldown = nextAllowedAt > DateTime.now().millisecondsSinceEpoch;
    final cooldownText = onCooldown
        ? (isAm
            ? 'ስም መልሶ መቀየር የሚችሉት ${_formatDate(nextAllowedAt, lang)} ጀምሮ ነው'
            : 'You can change your name again starting ${_formatDate(nextAllowedAt, lang)}')
        : (isAm ? 'ስም በወር አንድ ጊዜ ብቻ መቀየር ይቻላል' : 'Name can be changed once every 30 days');

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _labeled(
          context,
          isAm ? 'ስም' : 'NAME',
          TextField(
            controller: _nameCtrl,
            enabled: !onCooldown,
            keyboardType: TextInputType.name,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Text(cooldownText, style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: _labeled(
              context,
              isAm ? 'ኢሜል' : 'EMAIL',
              TextField(
                controller: TextEditingController(text: maskedEmail),
                readOnly: true,
                style: TextStyle(color: AppTheme.textMuted(context)),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _labeled(
              context,
              isAm ? 'ስልክ ቁጥር' : 'PHONE',
              TextField(
                controller: TextEditingController(text: app.user?.phone ?? ''),
                readOnly: true,
                style: TextStyle(color: AppTheme.textMuted(context)),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
          child: Text(
            isAm
                ? '🔒 ኢሜል እና ስልክ ቁጥር የመለያዎ ቋሚ መለያ በመሆናቸው ከዚህ ገጽ ሊቀየሩ አይችሉም።'
                : "🔒 Your email and phone number are your account's permanent identifiers and can't be changed from this screen.",
            style: TextStyle(fontSize: 12, color: AppTheme.tagText(context)),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: (onCooldown || _submittingName) ? null : () => _submitNameChange(context, app),
            child: _submittingName
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : Text(isAm ? 'አስቀምጥ' : 'Save', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
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

  Future<void> _submitNameChange(BuildContext context, AppState app) async {
    final lang = app.lang;
    final isAm = lang == 'am';
    final newName = _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (newName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('invalid_name', lang))));
      return;
    }
    if (newName == app.user?.name) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? 'ምንም ለውጥ አላደረጉም' : "You haven't changed anything")));
      return;
    }

    final password = await promptWalletPassword(context, isAm ? 'ስም ለመቀየር ፓስዎርድዎን ያስገቡ' : 'Enter your password to change your name');
    if (password == null || !mounted) return;

    setState(() => _submittingName = true);
    final (_, err) = await app.updateName(newName: newName, password: password);
    setState(() => _submittingName = false);
    if (!mounted) return;

    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '✅ ስም ተቀይሯል' : '✅ Name updated')));
      setState(() => _userFuture = app.checkPhone(app.user!.phone));
    } else {
      final msg = err == 'cooldown_active'
          ? (isAm ? '⚠️ ስም መልሶ ለመቀየር ገና 30 ቀን አልተጠናቀቀም' : "⚠️ It's not been 30 days since your last name change")
          : err == 'wrong_password'
              ? (isAm ? '❌ የተሳሳተ ፓስዎርድ' : '❌ Incorrect password')
              : (isAm ? 'ስህተት ተፈጥሯል' : 'Something went wrong');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ================================================================
  //  BASIC-TIER — 2-step wallet-activation wizard
  // ================================================================

  Widget _buildWizard(BuildContext context, AppState app, String lang, bool isAm) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _wizardProgress(context, lang, isAm),
        const SizedBox(height: 20),
        ..._wizardStepContent(context, app, lang, isAm),
      ],
    );
  }

  Widget _wizardProgress(BuildContext context, String lang, bool isAm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_wizardTotalSteps, (i) {
            final filled = i < _wizardStep;
            return Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i < _wizardTotalSteps - 1 ? 5 : 0),
                decoration: BoxDecoration(
                  color: filled ? AppTheme.brand : AppTheme.line(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isAm ? '🪙 ዋሌት ማግበሪያ' : '🪙 Wallet Activation',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text('$_wizardStep/$_wizardTotalSteps',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted(context))),
          ],
        ),
      ],
    );
  }

  List<Widget> _wizardStepContent(BuildContext context, AppState app, String lang, bool isAm) {
    switch (_wizardStep) {
      case 1:
        return _wizardStep1(context, isAm);
      default:
        return _wizardStep2(context, app, lang, isAm);
    }
  }

  Widget _wizardTitle(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context))),
          ],
        ),
      );

  Widget _wizardNav({VoidCallback? onBack, required VoidCallback? onNext, required String nextLabel}) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(
          children: [
            if (onBack != null) TextButton(onPressed: _wizardLoading ? null : onBack, child: Text(_lang == 'am' ? '← ተመለስ' : '← Back')),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
              onPressed: _wizardLoading ? null : onNext,
              child: _wizardLoading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(nextLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  String get _lang => context.read<AppState>().lang;

  Widget _wizardErrorText() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(_wizardError!, style: const TextStyle(color: AppTheme.danger)),
      );

  // ---- Step 1/2: name + password + confirm + promo code (optional) —
  // reuses the exact old register-step field labels/order, just without
  // email (which moved to step 2). No network call happens here — this
  // is purely local until "ላክ ኮድ" is pressed on step 2. ----
  List<Widget> _wizardStep1(BuildContext context, bool isAm) => [
        _wizardTitle(S.t('register_title', _lang), S.t('register_sub', _lang)),
        TextField(
          controller: _wizardNameCtrl,
          autofocus: true,
          keyboardType: TextInputType.name,
          decoration: InputDecoration(labelText: S.t('full_name', _lang), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        PasswordField(controller: _wizardPasswordCtrl, labelText: S.t('pin_code', _lang)),
        const SizedBox(height: 12),
        PasswordField(controller: _wizardPassword2Ctrl, labelText: S.t('pin_confirm', _lang)),
        const SizedBox(height: 12),
        TextField(
          controller: _wizardPromoCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: S.t('promo_code_label', _lang), border: const OutlineInputBorder()),
        ),
        if (_wizardError != null) _wizardErrorText(),
        _wizardNav(
          onNext: () {
            final name = _wizardNameCtrl.text.trim();
            final password = _wizardPasswordCtrl.text.trim();
            final password2 = _wizardPassword2Ctrl.text.trim();
            if (name.length < 2) {
              setState(() => _wizardError = S.t('invalid_name', _lang));
              return;
            }
            if (!_passwordRe.hasMatch(password)) {
              setState(() => _wizardError = S.t('invalid_password', _lang));
              return;
            }
            if (password != password2) {
              setState(() => _wizardError = S.t('pin_mismatch', _lang));
              return;
            }
            setState(() {
              _wizardError = null;
              _wizardStep = 2;
            });
          },
          nextLabel: isAm ? 'ቀጥል' : 'Next',
        ),
      ];

  // ---- Step 2/2: email, then the code box+button — ported to look
  // exactly like the old _verifyStep's Row(TextField + ElevatedButton),
  // just reachable without any code having been auto-sent first. No
  // code is ever sent until this button is actually pressed. ----
  List<Widget> _wizardStep2(BuildContext context, AppState app, String lang, bool isAm) => [
        _wizardTitle(S.t('enter_code_title', lang), S.t('migrate_sub', lang)),
        TextField(
          controller: _wizardEmailCtrl,
          autofocus: true,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: S.t('email_address', lang), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _wizardCodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: InputDecoration(
                    hintText: S.t('enter_code_placeholder', lang), border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_resendSeconds > 0 || _resendBlocked || _wizardLoading)
                  ? null
                  : () => _wizardSendOrResend(context, app, lang),
              child: _wizardLoading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(S.t('send_code_btn', lang)),
            ),
          ],
        ),
        if (_resendBlocked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(S.t('resend_limit_reached', lang), style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
          )
        else if (_resendSeconds > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              isAm ? 'ድጋሚ ላክ በ ${_resendSeconds}ሰ' : 'Resend in ${_resendSeconds}s',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
            ),
          ),
        if (_wizardError != null) _wizardErrorText(),
        _wizardNav(
          onBack: _codeSent
              ? null
              : () => setState(() {
                    _wizardError = null;
                    _wizardStep = 1;
                  }),
          onNext: _codeSent ? () => _confirmWizardCode(context, app, isAm) : null,
          nextLabel: S.t('confirm_code_btn', lang),
        ),
      ];

  /// The Row button next to the code field — first press validates the
  /// email and actually sends the code (this is the ONLY thing that
  /// triggers a send; nothing auto-sends); every press after that is a
  /// plain resend of the same pending code request.
  Future<void> _wizardSendOrResend(BuildContext context, AppState app, String lang) async {
    if (_resendSeconds > 0 || _resendBlocked) return;

    if (!_codeSent) {
      final email = _wizardEmailCtrl.text.trim();
      if (!_emailRe.hasMatch(email)) {
        setState(() => _wizardError = S.t('invalid_email', lang));
        return;
      }
      setState(() {
        _wizardLoading = true;
        _wizardError = null;
      });
      final err = await app.startMigrate(
        phone: app.user!.phone,
        email: email,
        password: _wizardPasswordCtrl.text.trim(),
        name: _wizardNameCtrl.text.trim(),
        incomingReferralCode: _wizardPromoCtrl.text.trim().isEmpty ? null : _wizardPromoCtrl.text.trim(),
      );
      setState(() => _wizardLoading = false);
      if (err == null) {
        _wizardCodeCtrl.clear();
        _startResendTimer();
        setState(() => _codeSent = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('code_sent', lang))));
      } else {
        setState(() => _wizardError = _wizardErrorText2(err, lang));
      }
      return;
    }

    final err = await app.resendMigrateCode();
    if (err == null) {
      _startResendTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('code_sent', lang))));
    } else if (mounted) {
      setState(() {
        _wizardError = _wizardErrorText2(err, lang);
        if (err == 'blocked') _resendBlocked = true;
      });
    }
  }

  Future<void> _confirmWizardCode(BuildContext context, AppState app, bool isAm) async {
    final code = _wizardCodeCtrl.text.trim();
    if (code.length < 5) {
      setState(() => _wizardError = S.t('wrong_code', app.lang));
      return;
    }
    setState(() {
      _wizardLoading = true;
      _wizardError = null;
    });
    final err = await app.completeMigrate(code);
    setState(() => _wizardLoading = false);
    if (err == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(isAm ? '✅ ዋሌትዎ ገብቷል!' : '✅ Wallet activated!')));
        setState(() => _userFuture = app.checkPhone(app.user!.phone));
      }
    } else {
      setState(() => _wizardError = _wizardErrorText2(err, app.lang));
    }
  }

  String _wizardErrorText2(String code, String lang) {
    switch (code) {
      case 'invalid_email':
        return S.t('invalid_email', lang);
      case 'invalid_password':
        return S.t('invalid_password', lang);
      case 'invalid_name':
        return S.t('invalid_name', lang);
      case 'already_registered':
      case 'email_mismatch':
        return S.t('already_registered', lang);
      case 'code_expired':
        return S.t('code_expired', lang);
      case 'wrong_code':
        return S.t('wrong_code', lang);
      case 'cooldown':
        return S.t('resend_wait', lang);
      case 'blocked':
        return S.t('resend_limit_reached', lang);
      case 'locked_try_later':
        return S.t('too_many_attempts', lang);
      default:
        return S.t('connection_error', lang);
    }
  }
}

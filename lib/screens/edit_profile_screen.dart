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

/// Doubles as the "Wallet Activation" form for basic-tier (phone+name
/// only) accounts — per Dani's request, this is reached directly when
/// tapping "የኔ ዋሌት" (My Wallet) from the profile menu instead of a
/// separate modal, since name/email/phone already live on this one
/// screen. Wallet-tier accounts see the original read-only
/// email/phone + editable (password-gated) name view unchanged.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late Future<Map<String, dynamic>?> _userFuture;
  final _nameCtrl = TextEditingController();

  // ---- Basic-tier wallet-activation fields — email + password are
  // independent TextFields (neither disables the other), but the
  // "Activate" button only proceeds once BOTH are valid together, per
  // Dani's decision to avoid a half-saved (e.g. password-only, no
  // recovery email) state. ----
  final _emailCtrl = TextEditingController();
  final _activatePasswordCtrl = TextEditingController();
  final _activatePassword2Ctrl = TextEditingController();
  final _activateCodeCtrl = TextEditingController();
  bool _activationCodeSent = false;
  bool _activating = false;
  String? _activationError;
  int _resendSeconds = 0;
  bool _resendBlocked = false;

  bool _submittingName = false;

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
    _emailCtrl.dispose();
    _activatePasswordCtrl.dispose();
    _activatePassword2Ctrl.dispose();
    _activateCodeCtrl.dispose();
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
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final u = snap.data ?? {};
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
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text(cooldownText, style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (onCooldown || _submittingName) ? null : () => _submitName(context, app, isBasic),
                  child: _submittingName
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isAm ? 'ስም አስቀምጥ' : 'Save name'),
                ),
              ),
              const SizedBox(height: 20),

              if (isBasic) ..._walletActivationSection(context, app, lang, isAm) else ..._walletTierSection(context, app, u, lang, isAm),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Wallet-tier (unchanged): read-only email+phone ----------------

  List<Widget> _walletTierSection(
      BuildContext context, AppState app, Map<String, dynamic> u, String lang, bool isAm) {
    final email = (u['email'] as String?) ?? '';
    final maskedEmail = email.isNotEmpty ? _maskEmail(email) : (isAm ? 'አልገባም' : 'Not set');
    return [
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
    ];
  }

  // ---------------- Basic-tier: editable email+password → wallet activation ----------------

  List<Widget> _walletActivationSection(BuildContext context, AppState app, String lang, bool isAm) {
    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.tagBg(context), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
        child: Text(
          isAm
              ? '🪙 የኮይን/ዋሌት አገልግሎት ለማግኘት ኢሜል እና ፓስዎርድ ማስገባት ያስፈልጋል። ስልክ ቁጥርዎ ቋሚ ነው፣ ሊቀየር አይችልም።'
              : "🪙 Coin/wallet features require an email and password. Your phone number is permanent and can't be changed.",
          style: TextStyle(fontSize: 12, color: AppTheme.tagText(context)),
        ),
      ),
      const SizedBox(height: 14),
      _labeled(
        context,
        isAm ? 'ስልክ ቁጥር' : 'PHONE',
        TextField(
          controller: TextEditingController(text: app.user?.phone ?? ''),
          readOnly: true,
          style: TextStyle(color: AppTheme.textMuted(context)),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
      ),
      const SizedBox(height: 12),
      _labeled(
        context,
        isAm ? 'ኢሜል' : 'EMAIL',
        TextField(
          controller: _emailCtrl,
          enabled: !_activationCodeSent,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _activatePasswordCtrl,
        labelText: S.t('pin_code', lang),
        enabled: !_activationCodeSent,
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _activatePassword2Ctrl,
        labelText: S.t('pin_confirm', lang),
        enabled: !_activationCodeSent,
      ),
      if (_activationError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_activationError!, style: const TextStyle(color: AppTheme.danger)),
        ),
      const SizedBox(height: 14),

      if (!_activationCodeSent)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _activating ? null : () => _startActivation(context, app, lang, isAm),
            child: _activating
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : Text(isAm ? '🪙 ዋሌት አግብር' : '🪙 Activate Wallet',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )
      else ...[
        Text(
          (isAm ? 'ኮድ ወደ ' : 'A code was sent to ') + _emailCtrl.text.trim(),
          style: TextStyle(color: AppTheme.textMuted(context)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _activateCodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: InputDecoration(
                    hintText: S.t('enter_code_placeholder', lang), border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_resendSeconds > 0 || _resendBlocked) ? null : () => _resendActivationCode(context, app),
              child: Text(S.t('send_code_btn', lang)),
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
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _activating ? null : () => _confirmActivation(context, app, isAm),
            child: _activating
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                : Text(S.t('confirm_code_btn', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ];
  }

  Future<void> _startActivation(BuildContext context, AppState app, String lang, bool isAm) async {
    final email = _emailCtrl.text.trim();
    final password = _activatePasswordCtrl.text.trim();
    final password2 = _activatePassword2Ctrl.text.trim();

    // Both email AND password (+confirm) must be complete together —
    // Dani's decision: no half-activated state (e.g. a password with no
    // recovery email, which would permanently lock the account out if
    // the phone+name were ever guessed).
    if (!_emailRe.hasMatch(email) || !_passwordRe.hasMatch(password) || password != password2) {
      setState(() {
        _activationError = !_emailRe.hasMatch(email)
            ? S.t('invalid_email', lang)
            : !_passwordRe.hasMatch(password)
                ? S.t('invalid_password', lang)
                : S.t('pin_mismatch', lang);
      });
      return;
    }

    setState(() {
      _activating = true;
      _activationError = null;
    });
    final err = await app.startMigrate(phone: app.user!.phone, email: email, password: password);
    setState(() => _activating = false);
    if (err == null) {
      _activateCodeCtrl.clear();
      _startResendTimer();
      setState(() => _activationCodeSent = true);
    } else {
      setState(() => _activationError = _activationErrorText(err, lang));
    }
  }

  Future<void> _resendActivationCode(BuildContext context, AppState app) async {
    if (_resendSeconds > 0 || _resendBlocked) return;
    final err = await app.resendMigrateCode();
    if (err == null) {
      _startResendTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('code_sent', app.lang))));
    } else if (mounted) {
      setState(() {
        _activationError = _activationErrorText(err, app.lang);
        if (err == 'blocked') _resendBlocked = true;
      });
    }
  }

  Future<void> _confirmActivation(BuildContext context, AppState app, bool isAm) async {
    final code = _activateCodeCtrl.text.trim();
    if (code.length < 5) {
      setState(() => _activationError = S.t('wrong_code', app.lang));
      return;
    }
    setState(() {
      _activating = true;
      _activationError = null;
    });
    final err = await app.completeMigrate(code);
    setState(() => _activating = false);
    if (err == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isAm ? '✅ ዋሌትዎ ገብቷል!' : '✅ Wallet activated!')));
        Navigator.of(context).pop();
      }
    } else {
      setState(() => _activationError = _activationErrorText(err, app.lang));
    }
  }

  String _activationErrorText(String code, String lang) {
    switch (code) {
      case 'invalid_email':
        return S.t('invalid_email', lang);
      case 'invalid_password':
        return S.t('invalid_password', lang);
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

  Widget _labeled(BuildContext context, String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted(context))),
          const SizedBox(height: 4),
          child,
        ],
      );

  // ---------------- Name change (shared, but credential differs by tier) ----------------

  Future<void> _submitName(BuildContext context, AppState app, bool isBasic) async {
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

    String? err;
    if (isBasic) {
      // Basic-tier has no password — re-entering the CURRENT name is
      // their credential, same as at login.
      final currentName = await _promptCurrentName(context, app.user?.name ?? '');
      if (currentName == null || !mounted) return;
      setState(() => _submittingName = true);
      (_, err) = await app.updateNameBasic(currentName: currentName, newName: newName);
    } else {
      final password = await promptWalletPassword(context, isAm ? 'ስም ለመቀየር ፓስዎርድዎን ያስገቡ' : 'Enter your password to change your name');
      if (password == null || !mounted) return;
      setState(() => _submittingName = true);
      (_, err) = await app.updateName(newName: newName, password: password);
    }
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
              : err == 'wrong_name'
                  ? S.t('wrong_name', lang)
                  : err == 'invalid_name'
                      ? S.t('invalid_name', lang)
                      : err == 'locked_try_later'
                          ? S.t('too_many_attempts', lang)
                          : (isAm ? 'ስህተት ተፈጥሯል' : 'Something went wrong');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Basic-tier equivalent of promptWalletPassword() — re-enter the
  /// account's current name to authorize a name change.
  Future<String?> _promptCurrentName(BuildContext context, String currentNameHint) async {
    final nameCtrl = TextEditingController();
    final lang = context.read<AppState>().lang;
    final isAm = lang == 'am';

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isAm ? '🔒 የአሁኑን ስምዎን ያረጋግጡ' : '🔒 Confirm your current name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAm ? 'ስም ለመቀየር የአሁኑን ስምዎን ዳግም ያስገቡ' : "Re-enter your current name to change it",
              style: TextStyle(color: AppTheme.textMuted(dialogContext)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(isAm ? 'ይቅር' : 'Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameCtrl.text.trim()),
            child: Text(isAm ? 'ቀጥል' : 'Continue'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/wallet_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'wallet_screen.dart' show promptWalletPassword; // reuse the shared password-confirm dialog

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

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late Future<Map<String, dynamic>?> _userFuture;
  final _nameCtrl = TextEditingController();
  bool _submitting = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.lang;
    final isAm = lang == 'am';

    return Scaffold(
      appBar: AppBar(title: Text('👤 ${S.t('edit_profile_menu', lang)}')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _userFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final u = snap.data ?? {};
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
                  onPressed: (onCooldown || _submitting) ? null : () => _submit(context, app),
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                      : Text(isAm ? 'አስቀምጥ' : 'Save', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
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
    final newName = _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (newName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '⚠️ ትክክለኛ ስም ያስገቡ' : '⚠️ Enter a valid name')));
      return;
    }
    if (newName == app.user?.name) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? 'ምንም ለውጥ አላደረጉም' : "You haven't changed anything")));
      return;
    }

    final password = await promptWalletPassword(context, isAm ? 'ስም ለመቀየር ፓስዎርድዎን ያስገቡ' : 'Enter your password to change your name');
    if (password == null || !mounted) return;

    setState(() => _submitting = true);
    final (_, err) = await app.updateName(newName: newName, password: password);
    setState(() => _submitting = false);
    if (!mounted) return;

    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAm ? '✅ ስም ተቀይሯል' : '✅ Name updated')));
      Navigator.of(context).pop();
    } else {
      final msg = err == 'cooldown_active'
          ? (isAm ? '⚠️ ስም መልሶ ለመቀየር ገና 30 ቀን አልተጠናቀቀም' : "⚠️ It's not been 30 days since your last name change")
          : err == 'wrong_password'
              ? (isAm ? '❌ የተሳሳተ ፓስዎርድ' : '❌ Incorrect password')
              : err == 'invalid_name'
                  ? (isAm ? '⚠️ ትክክለኛ ስም ያስገቡ' : '⚠️ Enter a valid name')
                  : (isAm ? 'ስህተት ተፈጥሯል' : 'Something went wrong');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

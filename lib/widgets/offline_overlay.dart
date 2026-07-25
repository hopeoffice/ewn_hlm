import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../services/connectivity_service.dart';

/// Ported from `#offline-overlay` in index.html + style.css —
/// `showOfflineOverlay()` is called before any network-dependent action
/// (login/register/forgot-PIN, checkout, buy-coins, help-center "send to
/// admin") when there's no connection, instead of letting the underlying
/// Firebase call hang silently. A full-screen overlay (not a small
/// dialog) matching the web's `position:fixed; inset:0` treatment, with
/// the same dark-green background, illustration, and
/// Try-Again/Cancel button pair.
///
/// Returns true if online (caller should proceed), false if the person
/// is still offline and dismissed it (caller should stop).
Future<bool> requireOnlineOrWarn(BuildContext context, String lang) async {
  if (await ConnectivityService.hasConnection()) return true;
  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    PageRouteBuilder(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _OfflineOverlay(lang: lang),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
  return result ?? false;
}

class _OfflineOverlay extends StatefulWidget {
  final String lang;
  const _OfflineOverlay({required this.lang});

  @override
  State<_OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<_OfflineOverlay> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    final online = await ConnectivityService.hasConnection();
    if (!mounted) return;
    if (online) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.lang == 'am' ? 'አሁንም ከመስመር ውጭ ነዎት' : 'Still offline')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return PopScope(
      canPop: false,
      child: Scaffold(
        // Mirrors .offline-overlay's `background: #0d5c42` exactly.
        backgroundColor: const Color(0xFF0D5C42),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '📡 ${S.t('offline_title', lang)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    S.t('offline_msg', lang),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                  ),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Image.asset('assets/illustrations/offline-illustration.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _checking ? null : () => Navigator.of(context).pop(false),
                      child: Text(S.t('cancel_btn', lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D5C42),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _checking ? null : _retry,
                      child: _checking
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D5C42)))
                          : Text(S.t('try_again', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

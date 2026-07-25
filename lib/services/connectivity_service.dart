import 'dart:io';

/// Ported from the `navigator.onLine` + `showOfflineOverlay()` guards used
/// throughout main-config.js/main-actions.js/main-ui.js before any action
/// that requires the network (login, register, checkout, buy-coins,
/// support messages). The Flutter app had NO equivalent guard anywhere —
/// on a slow/absent connection, a Firebase call would just hang with no
/// feedback (the loading spinner spinning forever) instead of a clear
/// "you're offline" message.
///
/// Implemented via a plain DNS lookup (no extra package/version to pin —
/// `connectivity_plus`'s API shape has changed across major versions, and
/// this environment has no Flutter/Dart SDK available to verify against
/// whichever version would actually resolve at build time). A short
/// timeout keeps this from stalling the UI itself while checking.
class ConnectivityService {
  static Future<bool> hasConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

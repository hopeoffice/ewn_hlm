import 'dart:convert';
import 'package:http/http.dart' as http;

/// Ported from checkForAppUpdate() / requestMandatoryUpdate() /
/// showSoftUpdate() in main-actions.js.
///
/// The web app reads a static `version.json` (served from the same
/// Firebase Hosting site) with `v` / `forceUpdate` / `minVersion` /
/// `updateMessage(Am)`. This service reads the *same* file — one single
/// admin-editable source of truth for both apps — but looks at
/// Android-specific keys (`androidVersion` / `androidMinVersion` /
/// `androidForceUpdate` / `androidStoreUrl`) so a web deploy never
/// falsely triggers an Android update prompt, and vice versa.
///
/// IMPORTANT for whoever wires up the admin panel: these `android*` keys
/// don't exist in version.json yet. Until they're added, `checkForUpdate()`
/// always returns null (no update signalled) — it never guesses.
class AppUpdateInfo {
  final bool mandatory;
  final String messageAm;
  final String messageEn;
  final String? storeUrl;
  const AppUpdateInfo({
    required this.mandatory,
    required this.messageAm,
    required this.messageEn,
    this.storeUrl,
  });
}

class UpdateService {
  UpdateService._();

  /// Bump this on every Play Store release. Mirrors the web app's own
  /// hardcoded `APP_VERSION` constant in main-config.js — the web app
  /// keeps its counter, this keeps ours; they're independent on purpose
  /// since the two apps ship on different schedules.
  static const int kAppVersion = 1;

  static const String _versionUrl = 'https://ewn-hlm.web.app/version.json';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final res = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final remoteVersionRaw = data['androidVersion'];
      if (remoteVersionRaw == null) return null; // admin hasn't set up Android gating yet
      final remoteVersion = int.tryParse(remoteVersionRaw.toString());
      if (remoteVersion == null || remoteVersion <= kAppVersion) return null;

      final minVersionRaw = data['androidMinVersion'];
      final minVersion = minVersionRaw != null ? int.tryParse(minVersionRaw.toString()) : null;
      final belowMin = minVersion != null && kAppVersion < minVersion;
      final forceUpdate = data['androidForceUpdate'] == true;

      return AppUpdateInfo(
        mandatory: forceUpdate || belowMin,
        messageAm: (data['updateMessageAm'] as String?) ?? 'አዲስ ማሻሻያ አለ — እባክዎ ያዘምኑ',
        messageEn: (data['updateMessage'] as String?) ?? 'A new update is available — please update',
        storeUrl: data['androidStoreUrl'] as String?,
      );
    } catch (_) {
      // offline / blocked / malformed JSON — same as the web app: stay
      // quiet and let the next poll (or focus/resume check) try again.
      return null;
    }
  }
}

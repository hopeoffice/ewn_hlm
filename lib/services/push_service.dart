import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_service.dart';

/// Step 3 of the migration plan — push notifications. The PWA had no
/// real push (browser notification permission prompts only); this gives
/// the native app real background/foreground push via FCM.
class PushService {
  static final _messaging = FirebaseMessaging.instance;
  static final _fb = FirebaseService();

  /// Call once after a successful login (needs the phone number to know
  /// which users/{phone}/fcmToken to write to).
  static Future<void> registerForUser(String phone) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await _messaging.getToken();
      if (token != null) {
        await _fb.saveFcmToken(phone, token);
      }

      // Keep the stored token fresh if FCM rotates it.
      _messaging.onTokenRefresh.listen((newToken) {
        _fb.saveFcmToken(phone, newToken).catchError((_) {});
      });
    } catch (e) {
      // Non-fatal by design — e.g. permission-denied until the
      // "fcmToken" database rule is added (see firebase_service.dart).
      // A push-registration failure must never crash the app.
      // ignore: avoid_print
      print('⚠️ Push registration skipped: $e');
    }
  }

  /// Call once at app startup (main.dart) to react to foreground pushes
  /// (e.g. "your order status changed") while the app is open.
  static void listenForeground(void Function(RemoteMessage) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}

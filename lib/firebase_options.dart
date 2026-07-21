import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Explicit FirebaseOptions, taken directly from the real
/// android/app/google-services.json (api_key / mobilesdk_app_id /
/// project_number) — this sidesteps the need for the
/// com.google.gms.google-services Gradle plugin to correctly generate
/// values.xml at build time, which is what was failing
/// ("FirebaseOptions ... values.xml" crash on first launch).
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDBXJBGhJKBA0-KTycLni1pvFOZfzSJW50',
    appId: '1:770896835814:android:70322375b0853a72aaf727',
    messagingSenderId: '770896835814',
    projectId: 'ewn-hlm',
    databaseURL: 'https://ewn-hlm-default-rtdb.firebaseio.com',
    storageBucket: 'ewn-hlm.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => android;
}

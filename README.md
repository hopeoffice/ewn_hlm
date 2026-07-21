# Ewn Hlm — Flutter (native) migration

ይህ ፕሮጀክት ከ `ewn-hlm.web.app` PWA ወደ Flutter የተመለሰ ኮድ ነው (Migration Plan
ደረጃ 1, 2, 3, 5 ተግባራዊ ሆነዋል፤ ደረጃ 4 — local storage — ቀድሞውኑ ተካቷል፤
ደረጃ 6 — store submission — ገና አልተካተተም)።

**ማስታወሻ፡** ይህ ኮድ በዚህ ውይይት ውስጥ (ያለ ኢንተርኔት access ባለው sandbox) ተጽፎ
**አልተሞከረም/አልተገነባም** (flutter pub get / flutter build አልተሰራም) —
Flutter SDK እና ኢንተርኔት በዚህ አካባቢ ስለሌለ። ከዚህ በታች ባሉት ደረጃዎች እርስዎ በራስዎ
ኮምፒዩተር ላይ ማስኬድ ያስፈልጋል።

## 0. የመጀመሪያ ጊዜ ብቻ — android/ folder ካልነበረ

ይህ ፕሮጀክት እንደተላከልዎት `lib/` እና `pubspec.yaml` ብቻ ይዟል (ንጹህ Dart ኮድ) —
`android/`, `ios/` ወዘተ የመሳሰሉ የመድረክ ፎልደሮች ገና አልተፈጠሩም። Android Studio ውስጥ
ፕሮጀክቱን ከፍተው ገና `android/` ፎልደር የማይታይ ከሆነ፣ በመጀመሪያ ይህን ያሂዱ (Terminal tab
ውስጥ፣ ከ `pubspec.yaml` ጋር በአንድ ቦታ ሆነው)፡
```
flutter create .
```
ይህ `android/`ን (ነባሪ `applicationId: com.example.ewn_hlm` ጋር — ከ
`google-services.json` ጋር በትክክል የሚገጣጠም) ይፈጥራል፣ የነበሩትን `lib/`/`pubspec.yaml`
ፋይሎችዎን አይነካም። ከዚያ በኋላ ወደ ደረጃ 1 ይቀጥሉ።

## 1. Prerequisites
- Flutter SDK (`flutter --version` should work) — or the Flutter plugin inside Android Studio
- ✅ Already done for you: `android/app/google-services.json` (from the
  Firebase Console "ewn-hlm" project) and the real Cloudflare Worker URL
  are already in this project.

## 2. Install dependencies
```
flutter pub get
```

## 3. Firebase ግንኙነት (already wired — just verify 2 things)
Since you registered the Android app directly in the Firebase Console
(not via `flutterfire configure`), Android reads Firebase config
natively from `android/app/google-services.json` — no Dart-side
`firebase_options.dart` is needed for an Android-only build.

Two things to check in **your existing** `android/build.gradle` and
`android/app/build.gradle` (don't recreate these files — Android Studio
already generated them when it scaffolded the project; just confirm):

**`android/build.gradle`** (root) — inside `buildscript { dependencies { ... } }`:
```gradle
classpath 'com.google.gms:google-services:4.4.2'
```

**`android/app/build.gradle`** — at the very bottom of the file:
```gradle
apply plugin: 'com.google.gms.google-services'
```
And confirm `applicationId` matches the package name inside
`google-services.json` exactly:
```gradle
defaultConfig {
    applicationId "com.example.ewn_hlm"   // must match google-services.json
    minSdkVersion 21                       // firebase_messaging/image_picker need 21+
    ...
}
```
If your `applicationId` is different, either change it to
`com.example.ewn_hlm`, or go back to the Firebase Console → Project
Settings → your Android app → change the package name to match, and
re-download `google-services.json`.

## 4. Cloudflare Worker URL — already set
`lib/services/firebase_service.dart` already points at:
```dart
static const String workerBaseUrl = 'https://ewn-hlm-telegram.hopeoffice.workers.dev';
```
(taken from your real `config.js` — `telegramReceiptFunctionUrl` /
`telegramMessageFunctionUrl` / `adminVerifyUrl` all live on this same
Worker, and so do `/awardReferralCoins`, `/awardSignupBonus`,
`/redeemCoins`, per `COIN_WORKER_BASE_URL` in `main-config.js`.)

## 5. Run
```
flutter run
```

## 6. Build the APK (Step 5 of the migration plan)
```
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk` — installable
directly on a phone without the Play Store (Step 6, store submission,
intentionally skipped per current scope).

## Android Studio ላይ ለሚሰሩ (APK Build)

Android Studio ውስጥ Flutter plugin ተጭኖ ካለ (Preferences → Plugins → "Flutter")፣
የ Flutter/Dart SDK ራሱ በራስ-ሰር ይታወቃል። ደረጃዎቹ፡-

1. **Open** → ይህን ፎልደር (`ewn_hlm_flutter/`) በ Android Studio ይክፈቱ (የ `pubspec.yaml` ያለበትን root)።
2. Android Studio ራሱ **"Pub get"** ይላል/ያሳያል — ይንኩት (ወይም ከታች Terminal tab ውስጥ `flutter pub get`)።
3. `android/app/google-services.json` ቀድሞ ገብቷል — Project panel ውስጥ ፈልገው ይኑር (ካልታየ "Android" view ን ወደ "Project Files" ይቀይሩ)። `android/build.gradle` እና `android/app/build.gradle` ውስጥ ከላይ ባለው ደረጃ 3 የተጠቀሱት 2 መስመሮች መኖራቸውን ያረጋግጡ።
4. Worker URL ቀድሞ ተስተካክሏል (ደረጃ 4 ከላይ) — ምንም ተጨማሪ ስራ የለም።
5. ከላይ ቀኝ **Device dropdown** → "Android Emulator" ወይም በ USB የተገናኘ ስልክ ይምረጡ → ▶️ Run ተጭነው ይሞክሩ።
6. APK ለመገንባት፦ **Build → Flutter → Build APK** (ወይም Terminal ላይ `flutter build apk --release`)።
   ውጤቱ፦ `build/app/outputs/flutter-apk/app-release.apk`

**የተለመዱ ስህተቶች፡**
- *"No Firebase App has been created"* → `google-services.json` በ `android/app/` ውስጥ አለመኖሩን ወይም ደረጃ 3 ላይ ያሉት 2 gradle መስመሮች አለመኖራቸውን ያመለክታል።
- *"File google-services.json is missing"* (Gradle build error) → ተመሳሳይ ችግር፣ ፋይሉ በትክክለኛው ቦታ (`android/app/google-services.json`) መሆኑን ያረጋግጡ።
- *applicationId mismatch* → `google-services.json` ውስጥ `package_name: "com.example.ewn_hlm"` ስለሆነ፣ `android/app/build.gradle` ውስጥ `applicationId` በትክክል `"com.example.ewn_hlm"` መሆን አለበት፤ ካልሆነ Firebase init በጸጥታ ይወድቃል (silent failure)።
- *Gradle sync ውድቅት* → Android Studio → File → Invalidate Caches / Restart ብዙ ጊዜ ይፈታዋል፤ ወይም Android Studio's bundled JDK ጋር Gradle ተኳሃኝ ስሪት መሆኑን ያረጋግጡ።
- *minSdkVersion ስህተት* (firebase_messaging/image_picker ስለሚፈልጉ) → `android/app/build.gradle` ውስጥ `minSdkVersion` ወደ **21+** ያድርጉ።

## What's ported vs. what's a stub
| Feature | Status |
|---|---|
| Product catalog (Firestore live stream + offline cache) | ✅ full logic |
| Cart (add/remove/qty, local + Realtime DB sync) | ✅ full logic |
| Likes | ✅ full logic |
| Login/Register (phone + 4-digit PIN, Realtime DB `users/`) | ✅ full logic |
| Session persistence (no expiry, until logout) | ✅ `flutter_secure_storage` |
| Orders list | ✅ full logic |
| Checkout / order placement | ✅ payment method selection, receipt photo → Telegram, coins-only → text notice |
| Wallet screen | ✅ live coin balance, redeem flow |
| **Referral / share screen** | ✅ own code generated at registration (`referralCode`/`referralIndex`), incoming code tracked + owner credited with atomic `referralCount` transaction + Worker coin award, native share sheet (`share_plus`) — see `lib/screens/referral_screen.dart` |
| Push notifications | ✅ foreground listener + token save; ⏳ background/terminated handler needs the snippet below added before shipping |
| Admin panel | 🚫 intentionally NOT migrated — stays as the existing `admin.html` web page |

## Push notifications — before shipping
Add this to `lib/main.dart`, above `main()`, for background/terminated-app pushes
(foreground already works out of the box):
```dart
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
```
then register it right after `Firebase.initializeApp()` in `main()`:
```dart
FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
```
Android also needs the `google-services.json` (from `flutterfire configure`)
and, for Android 13+, the `POST_NOTIFICATIONS` runtime permission — already
requested via `_messaging.requestPermission()` in `push_service.dart`.

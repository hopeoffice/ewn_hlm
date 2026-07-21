import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'state/app_state.dart';
import 'services/storage_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Step 1 — Android reads android/app/google-services.json natively
  // (added from the Firebase Console "ewn-hlm" project), so no explicit
  // FirebaseOptions object is needed here — Firebase.initializeApp()
  // picks it up automatically as long as the Google Services Gradle
  // plugin is applied. See README.md "Firebase ግንኙነት" section.
  await Firebase.initializeApp();

  // Step 4 — Hive (cart/likes/orders/product cache) + secure storage init.
  await StorageService.init();

  // Step 3 — foreground push notifications (background/terminated
  // handling needs a top-level @pragma('vm:entry-point') handler; see
  // README.md "Push notifications" section before shipping).
  PushService.listenForeground((msg) {
    // TODO: surface via a Snackbar/local notification once a
    // NavigatorKey/overlay is wired up. For now this just proves the
    // token registration + listener pipeline works end-to-end.
    // ignore: avoid_print
    print('📩 Foreground push: ${msg.notification?.title} — ${msg.notification?.body}');
  });

  runApp(const EwnHlmApp());
}

class EwnHlmApp extends StatelessWidget {
  const EwnHlmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..bootstrap(),
      child: MaterialApp(
        title: 'Ewn Hlm',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const RootScaffold(),
      ),
    );
  }
}

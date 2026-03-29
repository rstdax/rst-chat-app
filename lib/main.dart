import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/notifications/notification_repository.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/chat/presentation/main_layout.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// Create a global instance for the popup generator
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ============================================================================
// THIS IS THE FLUTTER EQUIVALENT OF YOUR `firebase-messaging-sw.js`
// It runs in the background even if the app is closed.
// ============================================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("[Background] Received message: ${message.notification?.title}");
}

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 1. Force the splash to disappear NO MATTER WHAT after 2 seconds
  // This is your ultimate insurance policy.
  Future.delayed(const Duration(seconds: 2), () {
    FlutterNativeSplash.remove();
  });

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Remove splash NOW before we even touch notifications
    FlutterNativeSplash.remove();

    // 3. Try to init notifications (Wrapped in its own safety box)
    _safeInitNotifications();
  } catch (e) {
    debugPrint("Critical Init Error: $e");
    FlutterNativeSplash.remove(); // Backup remove
  }

  runApp(const ProviderScope(child: RSTChatApp()));
}

// Separate function so a crash here doesn't stop main()
Future<void> _safeInitNotifications() async {
  try {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('notify_icon');
    await flutterLocalNotificationsPlugin.initialize(
      settings: InitializationSettings(
        android: initAndroid,
      ), // <--- Added 'settings:'
    );
    debugPrint("✅ Notifications Ready");
  } catch (e) {
    debugPrint("⚠️ Notification Init Failed (Bypassed): $e");
  }
}

class RSTChatApp extends ConsumerStatefulWidget {
  const RSTChatApp({super.key});

  @override
  ConsumerState<RSTChatApp> createState() => _RSTChatAppState();
}

class _RSTChatAppState extends ConsumerState<RSTChatApp> {
  @override
  void initState() {
    super.initState();
    // Ask for permission and get the token as soon as the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    // ---> WATCH THE DYNAMIC THEME PROVIDERS <---
    final currentThemeMode = ref.watch(themeModeProvider);
    final currentThemeColor = ref.watch(themeColorProvider);

    return MaterialApp(
      title: 'RST Chat',
      debugShowCheckedModeBanner: false,

      // ---> DYNAMIC THEME SETUP <---
      themeMode: currentThemeMode,
      theme: ThemeData(
        colorSchemeSeed: currentThemeColor,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: currentThemeColor,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),

      home: Consumer(
        builder: (context, ref, child) {
          final authState = ref.watch(authStateProvider);

          return authState.when(
            data: (user) {
              if (user != null) return const MainLayout();
              return const LoginScreen();
            },
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                Scaffold(body: Center(child: Text('Auth Error: $e'))),
          );
        },
      ),
    );
  }
}

// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'firebase_options.dart';
import 'screens/splash_screen.dart'; // Import the splash screen
import 'screens/onboarding_screen.dart';
import 'auth/landing.dart';
import 'auth/login.dart';
import 'auth/signup.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/streak_notification_manager.dart';
import 'services/fcm_service.dart';
import 'utils/theme_provider.dart';
import 'utils/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // Initialize Firebase (required for authentication check in splash screen)
  // Use platform-specific options (important for web builds)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notification services for TikTok-style engagement (mobile only)
  if (!kIsWeb) {
    try {
      // 1. Local notifications for scheduled reminders
      await NotificationService().init();
      if (kDebugMode) print('✅ Notification Service initialized');

      // 2. Streak notification manager for daily reminders
      await StreakNotificationManager().initializeStreakNotifications();
      if (kDebugMode) print('✅ Streak Notification Manager initialized');

      // 3. FCM for push notifications even when app is closed
      await FCMService().initialize();
      if (kDebugMode) print('✅ FCM Service initialized');
    } catch (e) {
      // Non-fatal: continue without scheduled notifications
      if (kDebugMode) print('⚠️ Notification initialization error: $e');
    }
  }

  runApp(
    // Wrap app with ChangeNotifierProvider for theme management
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const EcoPilotApp(),
    ),
  );
}

class EcoPilotApp extends StatelessWidget {
  const EcoPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to theme changes
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'EcoPilot',
      debugShowCheckedModeBanner: false,

      // Use centralized theme definitions
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode, // Dynamic theme switching
      // Named routes for consistent navigation
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/auth': (context) => const AuthLandingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

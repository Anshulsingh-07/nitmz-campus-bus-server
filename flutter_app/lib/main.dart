import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/bus_service.dart';
import 'services/notification_service.dart';
import 'controllers/map_navigation_controller.dart';
import 'screens/splash_screen.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await dotenv.load(fileName: '.env');
      } catch (e) {
        // Continue even if .env load fails (app can still use defaults)
        // Print warning for debugging in development.
        // In production, ensure the .env file is present or provide env vars.
        // ignore: avoid_print
        print('Warning: failed to load .env: $e');
      }

      // Global error handling to surface uncaught errors while debugging.
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        // ignore: avoid_print
        print('FlutterError caught: ${details.exceptionAsString()}');
        if (details.stack != null) {
          // ignore: avoid_print
          print(details.stack);
        }
      };

      // Replace the default red error screen with a gentler placeholder so the
      // app remains usable while we log errors for debugging.
      ErrorWidget.builder = (FlutterErrorDetails details) {
        // ignore: avoid_print
        print('ErrorWidget triggered: ${details.exceptionAsString()}');
        return Material(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'UI error occurred',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  details.exceptionAsString(),
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      };

      await NotificationService.initialize();
      runApp(const CampusBusTrackerApp());
    },
    (error, stack) {
      // ignore: avoid_print
      print('Uncaught zone error: $error');
      // ignore: avoid_print
      print(stack);
    },
  );
}

class CampusBusTrackerApp extends StatelessWidget {
  const CampusBusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => BusService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        Provider(create: (_) => ApiService()),
      ],
      child: MaterialApp(
        title: 'Campus Bus Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            primary: const Color(0xFF1565C0),
            secondary: const Color(0xFF42A5F5),
            background: const Color(0xFFF5F7FA),
          ),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1565C0),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 4,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

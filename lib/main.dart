import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/live_stream_screen.dart';

void main() {
  // Initialize media_kit
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(const DashcamPocApp());
}

class DashcamPocApp extends StatelessWidget {
  const DashcamPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dashcam POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        // Dark theme optimized for in-car use
        colorScheme: ColorScheme.dark(
          primary: Colors.blue.shade700,
          secondary: Colors.blue.shade400,
          surface: Colors.black,
          error: Colors.red.shade400,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const LiveStreamScreen(),
    );
  }
}

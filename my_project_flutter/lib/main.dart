// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'client.dart';
import 'screens/shake_safe_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeClient();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShakeSafe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07111F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE53935),
          secondary: Color(0xFF5B86E5),
          surface: Color(0xFF101C2C),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFF7F9FC),
          displayColor: const Color(0xFFF7F9FC),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const ShakeSafeScreen(),
    );
  }
}

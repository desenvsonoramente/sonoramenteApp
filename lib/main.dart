import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:screen_protector/screen_protector.dart';

import 'widgets/auth_gate.dart';
import 'components/session_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const Color appBgColor = Color(0xFFA8C3B0);

  @override
  void initState() {
    super.initState();
    _initScreenProtection();
  }

  Future<void> _initScreenProtection() async {
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageOn();
    } catch (_) {
      // Alguns emuladores e Android 13+ ignoram essa API
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: appBgColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: appBgColor,
          elevation: 0,
          foregroundColor: Colors.black,
          centerTitle: true,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: appBgColor,
          surface: appBgColor,
        ),
      ),
      builder: (context, child) {
        // ✅ SessionGuard precisa ficar ABAIXO do MaterialApp
        // para ter ScaffoldMessenger / Navigator disponíveis.
        return SessionGuard(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}

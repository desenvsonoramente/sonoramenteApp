import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:screen_protector/screen_protector.dart';
import 'widgets/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 🔒 BLOQUEIA PRINT E GRAVAÇÃO GLOBALMENTE
  await ScreenProtector.preventScreenshotOn();
  await ScreenProtector.protectDataLeakageOn();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color appBgColor = Color(0xFFA8C3B0);

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

      home: const AuthGate(),
    );
  }
}

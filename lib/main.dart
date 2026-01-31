import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'widgets/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color appBgColor = Color(0xFFA8C3B0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // 🔒 DESATIVA MATERIAL 3 (previne efeitos indesejados)
      theme: ThemeData(
        useMaterial3: false,

        // 🎨 COR GLOBAL DO APP
        scaffoldBackgroundColor: appBgColor,

        appBarTheme: const AppBarTheme(
          backgroundColor: appBgColor,
          elevation: 0,
          foregroundColor: Colors.black,
          centerTitle: true,
        ),

        // 🔄 REMOVE EFEITO DE COR DIFERENTE NO OVERSCROLL
        colorScheme: ColorScheme.fromSeed(
          seedColor: appBgColor,
          surface: appBgColor, // ✅ substituído background deprecated
        ),
      ),

      home: const AuthGate(),
    );
  }
}

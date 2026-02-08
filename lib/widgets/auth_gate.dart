import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pages/login_page.dart';
import '../pages/home_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ⏳ Firebase inicializando
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ Não autenticado
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        // ✅ Autenticado
        // A validação de "login único" fica no SessionGuard (em main.dart),
        // para evitar corrida/loop de signOut durante criação/atualização do doc.
        return const HomePage();
      },
    );
  }
}

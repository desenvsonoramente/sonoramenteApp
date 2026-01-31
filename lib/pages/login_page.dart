import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/user_service.dart';
import '../services/device_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool loading = false;
  String? error;

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'user-not-found':
        return 'Nenhuma conta encontrada para esse e-mail.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-disabled':
        return 'Essa conta foi desativada.';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente novamente mais tarde.';
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      default:
        return 'Erro ao fazer login. Tente novamente.';
    }
  }

  Future<void> loginEmail() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );

      final user = cred.user;
      if (user != null) {
        final deviceId = await DeviceService.getDeviceId();
        await UserService().createUserIfNotExists(
          name: user.displayName ?? '',
          email: user.email ?? '',
          deviceId: deviceId,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (_) {
      setState(() {
        error = 'Erro inesperado. Tente novamente.';
      });
    }

    setState(() => loading = false);
  }

  Future<void> loginGoogle() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => loading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;

      if (user != null) {
        final deviceId = await DeviceService.getDeviceId();
        await UserService().createUserIfNotExists(
          name: user.displayName ?? '',
          email: user.email ?? '',
          deviceId: deviceId,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (_) {
      setState(() {
        error = 'Erro ao entrar com Google.';
      });
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFA8C3B0),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFEFE6D8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Entrar',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : loginEmail,
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: loading ? null : loginGoogle,
                    child: const Text('Entrar com Google'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterPage(),
                      ),
                    );
                  },
                  child: const Text('Criar conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

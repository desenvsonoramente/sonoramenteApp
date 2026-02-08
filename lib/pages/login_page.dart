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

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'user-not-found':
        return 'Esse e-mail NÃO está cadastrado.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-disabled':
        return 'Conta desativada.';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente mais tarde.';
      default:
        return 'Erro ao fazer login.';
    }
  }

  // ================= LOGIN EMAIL =================

  Future<void> loginEmail() async {
    print("🧠 LOGIN_EMAIL -> CLICK");
    print(
      "🧠 LOGIN_EMAIL -> EMAIL=${emailCtrl.text.trim()} | PASS_LEN=${passCtrl.text.trim().length}",
    );

    if (!mounted) return;
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
      if (user == null) throw Exception('Login falhou');

      print("🧠 LOGIN_EMAIL -> SIGN IN OK | UID=${user.uid}");

      final deviceId = await DeviceService.getDeviceId();

      await UserService().createUserIfNotExists(
        name: user.displayName ?? '',
        email: user.email ?? '',
        deviceId: deviceId,
      );

      // ✅ LOGIN ÚNICO: sempre atualiza o deviceIdAtivo
      print("🧠 LOGIN_EMAIL -> SET_ACTIVE_DEVICE -> $deviceId");
      await UserService().setActiveDevice(deviceId: deviceId);
      print("✅ LOGIN_EMAIL -> SET_ACTIVE_DEVICE OK");
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Erro inesperado.';
      });
    } finally {
      print("🧠 LOGIN_EMAIL -> FINALLY");
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  // ================= GOOGLE LOGIN =================

  Future<void> loginGoogle() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final googleSignIn = GoogleSignIn(scopes: ['email']);

      // Forçar escolha de conta
      final signedInUser = await googleSignIn.signInSilently();
      if (signedInUser != null) {
        await googleSignIn.signOut();
      }

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // usuário cancelou login

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(credential);

      final user = cred.user;
      if (user == null) throw Exception('Google login falhou');

      final deviceId = await DeviceService.getDeviceId();

      await UserService().createUserIfNotExists(
        name: user.displayName ?? '',
        email: user.email ?? '',
        deviceId: deviceId,
      );

      // ✅ LOGIN ÚNICO: sempre atualiza o deviceIdAtivo
      print("🧠 LOGIN_GOOGLE -> SET_ACTIVE_DEVICE -> $deviceId");
      await UserService().setActiveDevice(deviceId: deviceId);
      print("✅ LOGIN_GOOGLE -> SET_ACTIVE_DEVICE OK");
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Erro ao entrar com Google.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  // ================= UI =================

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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                  ),
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

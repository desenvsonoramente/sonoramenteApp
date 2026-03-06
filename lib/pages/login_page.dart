import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  String _appVersion = '';

  void _log(String msg) {
    // ignore: avoid_print
    print('🔐 [LoginPage] $msg');
  }

  void _warn(String msg) {
    // ignore: avoid_print
    print('⚠️ [LoginPage] $msg');
  }

  void _err(String msg) {
    // ignore: avoid_print
    print('❌ [LoginPage] $msg');
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      _warn('_loadVersion() falhou | $e');
    }
  }

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
      case 'invalid-credential':
        return 'E-mail ou senha inválidos.';
      default:
        return 'Erro ao fazer login.';
    }
  }

  Future<void> _syncUserOnBackend(User user) async {
    _log('_syncUserOnBackend() start | uid=${user.uid} email=${user.email}');

    final deviceId = await DeviceService.getDeviceId();
    _log('_syncUserOnBackend() deviceId=$deviceId');

    await UserService()
        .createUserIfNotExists(
          name: user.displayName ?? '',
          email: user.email ?? '',
          deviceId: deviceId,
        )
        .timeout(const Duration(seconds: 12));

    _log('_syncUserOnBackend() ok | uid=${user.uid}');
  }

  // ================= LOGIN EMAIL =================

  Future<void> loginEmail() async {
    if (!mounted) return;

    final email = emailCtrl.text.trim();
    final password = passCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        error = 'Preencha e-mail e senha.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      _log('loginEmail() start | email=$email');

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        throw Exception('Login falhou: user=null');
      }

      _log('loginEmail() auth ok | uid=${user.uid}');

      try {
        await _syncUserOnBackend(user);
      } catch (e) {
        _err('loginEmail() backend sync falhou | uid=${user.uid} | $e');

        if (!mounted) return;
        setState(() {
          error =
              'Login realizado, mas houve falha ao sincronizar sua sessão. Tente novamente.';
        });

        // ✅ Aqui NÃO fazemos signOut automático.
        // O motivo é: o problema precisa aparecer claramente,
        // em vez de mascarar como “volta para tela de login”.
      }
    } on FirebaseAuthException catch (e) {
      _err('loginEmail() FirebaseAuthException | code=${e.code} msg=${e.message}');
      if (!mounted) return;
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (e) {
      _err('loginEmail() erro inesperado | $e');
      if (!mounted) return;
      setState(() {
        error = 'Erro inesperado.';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
      _log('loginEmail() end');
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
      _log('loginGoogle() start');

      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final signedInUser = await googleSignIn.signInSilently();
      if (signedInUser != null) {
        _log('loginGoogle() havia sessão anterior Google -> signOut');
        await googleSignIn.signOut();
      }

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        _warn('loginGoogle() cancelado pelo usuário');
        if (mounted) {
          setState(() {
            loading = false;
          });
        }
        return;
      }

      _log('loginGoogle() googleUser ok | email=${googleUser.email}');

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || accessToken == null) {
        _warn('loginGoogle() idToken/accessToken ausente');
        if (mounted) {
          setState(() {
            loading = false;
            error =
                'Login com Google não retornou dados. No Firebase Console, adicione a impressão digital SHA-1 do seu app Android.';
          });
        }
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      final cred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = cred.user;
      if (user == null) {
        throw Exception('Google login falhou: user=null');
      }

      _log('loginGoogle() auth ok | uid=${user.uid}');

      try {
        await _syncUserOnBackend(user);
      } catch (e) {
        _err('loginGoogle() backend sync falhou | uid=${user.uid} | $e');

        if (!mounted) return;
        setState(() {
          error =
              'Login realizado, mas houve falha ao sincronizar sua sessão. Tente novamente.';
        });

        // ✅ Mesmo comportamento do login email:
        // não derruba silenciosamente, mostra erro real.
      }
    } on FirebaseAuthException catch (e) {
      _err('loginGoogle() FirebaseAuthException | code=${e.code} msg=${e.message}');
      if (!mounted) return;
      setState(() {
        error = _mapAuthError(e);
      });
    } on PlatformException catch (e) {
      _err('loginGoogle() PlatformException | code=${e.code} msg=${e.message}');
      if (!mounted) return;

      final code = e.code;
      final msg = e.message ?? '';

      setState(() {
        if (code == 'sign_in_failed' ||
            msg.contains('DEVELOPER_ERROR') ||
            msg.contains('12501')) {
          error =
              'Configuração do Google incorreta. No Firebase Console, adicione a impressão digital SHA-1 do app Android e ative "Entrar com Google".';
        } else {
          error = 'Erro ao entrar com Google. ${msg.isNotEmpty ? msg : code}';
        }
      });
    } catch (e) {
      _err('loginGoogle() erro inesperado | $e');
      if (!mounted) return;
      setState(() {
        error =
            'Erro ao entrar com Google. Confira no Firebase Console se o SHA-1 do app está cadastrado.';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
      _log('loginGoogle() end');
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
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                  ),
                  child: const Text('Criar conta'),
                ),
                const SizedBox(height: 12),
                if (_appVersion.isNotEmpty)
                  Text(
                    'v$_appVersion',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
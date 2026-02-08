import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ReauthPage extends StatefulWidget {
  final Future<void> Function() onSuccess;

  const ReauthPage({
    super.key,
    required this.onSuccess,
  });

  @override
  State<ReauthPage> createState() => _ReauthPageState();
}

class _ReauthPageState extends State<ReauthPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    emailCtrl.text = user?.email ?? '';
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar identidade'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Por segurança, confirme sua identidade para continuar.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            // EMAIL (somente leitura)
            TextField(
              controller: emailCtrl,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Email'),
            ),

            const SizedBox(height: 12),

            // SENHA (para email/password)
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
              ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: loading ? null : reauthenticate,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> reauthenticate() async {
    setState(() {
      loading = true;
      error = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        error = 'Usuário não logado.';
        loading = false;
      });
      return;
    }

    try {
      final providers = user.providerData.map((p) => p.providerId).toList();
      final isGoogle = providers.contains('google.com');

      if (isGoogle) {
        // 🔹 Reauth via Google
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() {
            error = 'Login Google cancelado.';
          });
          return;
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await user.reauthenticateWithCredential(credential);
      } else {
        // 🔹 Reauth via email/password
        final credential = EmailAuthProvider.credential(
          email: emailCtrl.text.trim(),
          password: passCtrl.text.trim(),
        );
        await user.reauthenticateWithCredential(credential);
      }

      // 🔹 Sucesso: executa callback
      await widget.onSuccess();

      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? 'Erro ao autenticar';
      });
    } catch (e) {
      setState(() {
        error = 'Erro inesperado: $e';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

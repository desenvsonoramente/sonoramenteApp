import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

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
              'Por segurança, confirme sua senha para continuar.',
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

    try {
      await AuthService.reauthenticateWithPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );

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
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }
}

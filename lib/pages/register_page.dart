import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool loading = false;
  String? error;

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'A senha deve ter no mínimo 6 caracteres.';
      case 'email-already-in-use':
        return 'Esse e-mail já está em uso.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'operation-not-allowed':
        return 'Criação de conta não permitida.';
      default:
        return 'Erro ao criar conta. Tente novamente.';
    }
  }

  Future<void> register() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      // 1️⃣ Cria usuário no Firebase Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
      final user = cred.user!;
      final name = nameCtrl.text.trim();

      // 2️⃣ Atualiza nome no Auth
      await user.updateDisplayName(name);
      await user.reload();

      // 3️⃣ Cria documento no Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'name': name,
        'plan': 'gratis',
        'addons': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // 4️⃣ Volta para a tela anterior
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        error = _mapAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Erro inesperado. Tente novamente.';
      });
    }

    if (!mounted) return;
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
                  'Criar conta',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 8),
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
                    onPressed: loading ? null : register,
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cadastrar'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

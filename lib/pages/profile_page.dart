import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_service.dart';
import '../pages/reauth_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final Color bgColor = const Color(0xFFA8C3B0);
  final Color boxColor = const Color(0xFFEFE6D8);

  final Uri _privacyPolicyUri = Uri.parse(
    'https://vanessarabello.com.br/sonoramente_politicaprivacidade.html',
  );

  final UserService _userService = UserService();

  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // ✅ Não empilha LoginPage manualmente.
    // Apenas volta para a raiz e deixa o AuthGate decidir.
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });

      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('Perfil'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    user.displayName ?? 'Usuário',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    user.email ?? '',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      side: const BorderSide(color: Colors.black12),
                    ),
                    onPressed: _openPrivacyPolicy,
                    child: const Text('Política de Privacidade'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _deleting ? null : confirmDeleteAccount,
                    child: _deleting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Excluir conta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final launched = await launchUrl(
        _privacyPolicyUri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      if (!launched) {
        _showSnackBar('Não foi possível abrir a Política de Privacidade');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Erro ao abrir política de privacidade');
    }
  }

  void confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir conta'),
        content: const Text(
          'Essa ação é permanente.\nTodos os seus dados serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await deleteAccount();
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_deleting) return;

    setState(() => _deleting = true);

    try {
      // ✅ deleteAccount() já faz signOut no UserService
      await _userService.deleteAccount();

      if (!mounted) return;

      // ✅ Volta para a raiz.
      // O AuthGate, na raiz, mostrará LoginPage sozinho.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'requires-recent-login') {
        _showSnackBar('Confirme sua identidade para excluir a conta');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReauthPage(
              onSuccess: () async {
                try {
                  await _userService.deleteAccount();
                  if (!mounted) return;

                  Navigator.of(context).popUntil((route) => route.isFirst);
                } catch (_) {
                  if (!mounted) return;
                  _showSnackBar('Erro ao excluir conta após reautenticação');
                }
              },
            ),
          ),
        );
      } else {
        _showSnackBar('Erro ao excluir: ${e.message}');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Erro desconhecido ao excluir conta');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
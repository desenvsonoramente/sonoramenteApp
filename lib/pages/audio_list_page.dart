import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/audio_model.dart';
import '../services/user_service.dart';
import '../components/audio_player.dart';
import 'premium_page.dart';

class AudioListPage extends StatefulWidget {
  final String mood;
  const AudioListPage({super.key, required this.mood});

  @override
  State<AudioListPage> createState() => _AudioListPageState();
}

class _AudioListPageState extends State<AudioListPage> {
  final UserService _userService = UserService();

  final Color bgColor = const Color(0xFFA8C3B0);
  final Color cardColor = const Color(0xFFEFE6D8);

  bool _loading = true;
  List<AudioModel> _audios = [];
  final Map<String, bool> _accessMap = {};

  @override
  void initState() {
    super.initState();
    _loadAudios();
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  bool _isFree(AudioModel a) => a.requiredBase.trim() == 'gratis';

  Future<void> _loadAudios() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _audios = [];
          _accessMap.clear();
          _loading = false;
        });
        _showSnack(
          'Você precisa estar logada para carregar os áudios.',
          color: Colors.red,
        );
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('audios')
          .where('category', isEqualTo: widget.mood)
          .get();

      final audios = query.docs
          .map((d) => AudioModel.fromMap(d.id, d.data()))
          .toList();

      // Ordenação:
      // 1) grátis
      // 2) todo o resto (premium)
      audios.sort((a, b) {
        final af = _isFree(a);
        final bf = _isFree(b);
        if (af && !bf) return -1;
        if (!af && bf) return 1;
        return 0;
      });

      if (!mounted) return;
      setState(() {
        _audios = audios;
        _accessMap.clear();
        _loading = false;
      });

      // Pré-preenche: grátis sempre liberado
      for (final a in audios) {
        if (_isFree(a)) _accessMap[a.id] = true;
      }
      if (mounted) setState(() {});

      // Calcula acesso no background
      for (final audio in audios) {
        if (_isFree(audio)) continue;

        _userService.canAccessAudio(audio: audio).then((canAccess) {
          if (!mounted) return;
          setState(() => _accessMap[audio.id] = canAccess);
        }).catchError((_) {
          if (!mounted) return;
          setState(() => _accessMap[audio.id] = false);
        });
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _audios = [];
        _accessMap.clear();
        _loading = false;
      });

      if (e.code == 'permission-denied') {
        _showSnack(
          'Sem permissão para carregar os áudios. Faça login novamente.',
          color: Colors.red,
        );
      } else {
        _showSnack(
          'Erro ao carregar áudios (${e.code}).',
          color: Colors.red,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _audios = [];
        _accessMap.clear();
        _loading = false;
      });

      _showSnack(
        'Erro inesperado ao carregar os áudios.',
        color: Colors.red,
      );
    }
  }

  void _onTapAudio(AudioModel audio, bool locked) {
    if (locked) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PremiumPage()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AudioPlayerModal(audio: audio),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Image.asset(
                    'assets/images/sonoramente_logo.png',
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
                Expanded(
                  child: _audios.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum áudio encontrado.',
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _audios.length,
                          itemBuilder: (context, index) {
                            final audio = _audios[index];

                            final isFree = _isFree(audio);

                            final canAccess =
                                isFree ? true : (_accessMap[audio.id] ?? false);
                            final locked = !canAccess;

                            return GestureDetector(
                              onTap: () => _onTapAudio(audio, locked),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    )
                                  ],
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            audio.title,
                                            style: TextStyle(
                                              fontWeight: isFree
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            audio.description,
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Badges:
                                    if (isFree)
                                      _badge('GRÁTIS', Colors.green)
                                    else ...[
                                      const SizedBox(width: 8),
                                      _badge('PREMIUM',
                                          const Color(0xFFB8860B)), // dourado
                                    ],

                                    const SizedBox(width: 8),

                                    Icon(
                                      locked
                                          ? Icons.lock_outline
                                          : Icons.play_arrow,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white, // ✅ texto branco (inclusive no dourado)
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
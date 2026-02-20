import 'package:flutter/material.dart';
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

  Future<void> _loadAudios() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      print('📌 [AudioListPage] _loadAudios start | mood=${widget.mood}');

      final query = await FirebaseFirestore.instance
          .collection('audios')
          .where('category', isEqualTo: widget.mood)
          .get();

      print('✅ [AudioListPage] Firestore ok | docs=${query.docs.length}');

      final audios = query.docs
          .map((d) => AudioModel.fromMap(d.id, d.data()))
          .toList();

      // 🔹 Grátis sempre no topo
      audios.sort((a, b) {
        if (a.requiredBase == 'gratis' && b.requiredBase != 'gratis') return -1;
        if (a.requiredBase != 'gratis' && b.requiredBase == 'gratis') return 1;
        return 0;
      });

      // ✅ Mostra a lista IMEDIATAMENTE (não depende de claims/acesso)
      if (!mounted) return;
      setState(() {
        _audios = audios;
        _loading = false;
      });

      // ✅ Pré-preenche acessos: grátis é sempre true
      for (final a in audios) {
        if (a.requiredBase == 'gratis') {
          _accessMap[a.id] = true;
        }
      }
      if (mounted) setState(() {});

      // ✅ Calcula acessos em background (sem travar UI)
      for (final audio in audios) {
        if (audio.requiredBase == 'gratis') continue;

        _userService
            .canAccessAudio(audio: audio)
            .then((canAccess) {
              if (!mounted) return;
              setState(() => _accessMap[audio.id] = canAccess);
            })
            .catchError((e, st) {
              // Se falhar, mantém bloqueado, mas NUNCA some com a lista
              print('⚠️ [AudioListPage] canAccessAudio erro | audio=${audio.id} | $e');
              print(st);
              if (!mounted) return;
              setState(() => _accessMap[audio.id] = false);
            });
      }
    } catch (e, st) {
      print('❌ [AudioListPage] Firestore falhou: $e');
      print(st);

      if (!mounted) return;
      setState(() {
        _audios = [];
        _accessMap.clear();
        _loading = false;
      });
    }
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
                            final isFree = audio.requiredBase == 'gratis';

                            // ✅ Grátis não depende de mapa (definitivo)
                            final canAccess = isFree ? true : (_accessMap[audio.id] ?? false);
                            final locked = !canAccess;

                            // ✅ “Premium” = não grátis e está bloqueado
                            final isPremiumLocked = locked && !isFree;

                            return GestureDetector(
                              onTap: () {
                                if (locked) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PremiumPage(),
                                    ),
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
                              },
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            audio.title,
                                            style: TextStyle(
                                              fontWeight: isFree ? FontWeight.bold : null,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            audio.description,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ✅ Badges
                                    if (isFree) _badge('GRÁTIS', Colors.green),
                                    if (isPremiumLocked) ...[
                                      const SizedBox(width: 8),
                                      _badge('PREMIUM', const Color(0xFFB8860B)), // dourado
                                    ],

                                    const SizedBox(width: 8),

                                    Icon(
                                      locked ? Icons.lock_outline : Icons.play_arrow,
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
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
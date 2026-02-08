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
    setState(() => _loading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('audios')
          .where('category', isEqualTo: widget.mood)
          .get();

      final audios = query.docs
          .map((d) => AudioModel.fromMap(d.id, d.data()))
          .toList();

      // 🔹 Grátis sempre no topo
      audios.sort((a, b) {
        if (a.requiredBase == 'gratis' && b.requiredBase != 'gratis') return -1;
        if (a.requiredBase != 'gratis' && b.requiredBase == 'gratis') return 1;
        return 0;
      });

      // 🔹 Verifica acesso de todos os áudios
      final accessFutures = audios.map((audio) async {
        final canAccess = await _userService.canAccessAudio(audio: audio);
        return MapEntry(audio.id, canAccess);
      }).toList();

      final accessResults = await Future.wait(accessFutures);
      _accessMap
        ..clear()
        ..addEntries(accessResults);

      if (!mounted) return;
      setState(() {
        _audios = audios;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _audios.length,
                    itemBuilder: (context, index) {
                      final audio = _audios[index];
                      final locked = !(_accessMap[audio.id] ?? false);
                      final isFree = audio.requiredBase == 'gratis';

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
                              builder: (_) =>
                                  AudioPlayerModal(audio: audio),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      audio.title,
                                      style: TextStyle(
                                        fontWeight: isFree
                                            ? FontWeight.bold
                                            : null,
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
                              if (isFree)
                                _badge('GRÁTIS', Colors.green),
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
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

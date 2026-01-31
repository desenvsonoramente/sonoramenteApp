import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_service.dart';
import '../pages/premium_page.dart';

class AudioPlayerService {
  // ================= SINGLETON =================
  static final AudioPlayerService _instance =
      AudioPlayerService._internal();

  factory AudioPlayerService() => _instance;

  AudioPlayerService._internal() {
    _player.playerStateStream.listen((state) {
      debugPrint(
        "🎧 PlayerState -> playing: ${state.playing}, processing: ${state.processingState}",
      );
    });
  }

  // ================= CORE =================
  final AudioPlayer _player = AudioPlayer();
  final UserService _userService = UserService();

  AudioPlayer get player => _player;

  // ================= STREAMS (UI) =================
  Stream<PlayerState> get playerStateStream =>
      _player.playerStateStream;

  Stream<Duration?> get durationStream =>
      _player.durationStream;

  Stream<Duration> get positionStream =>
      _player.positionStream;

  bool get isPlaying => _player.playing;

  // ================= PLAY =================
  Future<void> play({
    required String url,
    required bool isFreeAudio,
    required BuildContext context,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      final canAccess =
          await _userService.canAccessAudio(isFreeAudio: isFreeAudio);

      if (!canAccess) {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PremiumPage(),
          ),
        );
        return;
      }

      // 🔁 evita recarregar o mesmo áudio
      if (_player.audioSource == null ||
          _player.audioSource.toString() != url) {
        await _player.setUrl(url);
      }

      await _player.play();
    } catch (e) {
      debugPrint('❌ Erro ao tocar áudio: $e');
    }
  }

  // ================= CONTROLES =================
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  // ================= CLEAN =================
  void dispose() {
    _player.dispose();
  }
}

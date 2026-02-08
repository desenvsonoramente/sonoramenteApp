import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/audio_model.dart';
import '../services/user_service.dart';
import '../pages/premium_page.dart';

class AudioPlayerService {
  // ================= SINGLETON =================
  static final AudioPlayerService _instance =
      AudioPlayerService._internal();

  factory AudioPlayerService() => _instance;

  AudioPlayerService._internal();

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
    required AudioModel audio,
    required BuildContext context,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final canAccess =
          await _userService.canAccessAudio(audio: audio);

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
          _player.audioSource.toString() != audio.audioUrl) {
        await _player.setUrl(audio.audioUrl);
      }

      await _player.play();
    } catch (_) {
      // silencioso em produção
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

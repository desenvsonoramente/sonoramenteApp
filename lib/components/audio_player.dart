import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/audio_model.dart';
import '../services/user_service.dart';
import '../pages/premium_page.dart';

class AudioPlayerModal extends StatefulWidget {
  final AudioModel audio;

  const AudioPlayerModal({
    super.key,
    required this.audio,
  });

  @override
  State<AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<AudioPlayerModal>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final UserService _userService = UserService();

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  double volume = 1.0;

  late AnimationController _pulseController;

  static const Color appGreen = Color(0xFF8FB8A6);
  static const Color backgroundColor = Color(0xFFFBFAF7);

  // Cache simples: key -> downloadUrl
  final Map<String, String> _urlCache = {};

  bool _listenersAttached = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    _init();
  }

  void _attachListenersOnce() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => duration = d);
    });

    _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => position = p);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() => isPlaying = state.playing);

      if (state.playing) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    });
  }

  /// Regras novas:
  /// - Firestore deve vir com: "gratis/arquivo.wav" ou "basico/arquivo.wav"
  /// - Compatível com URL antiga http(s)
  /// - Compatível com dado antigo "arquivo.wav" (assumimos gratis/)
  List<String> _candidateStorageKeys(String urlOrPath) {
    final raw = urlOrPath.trim();

    // URL antiga (dados legados)
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return [raw];
    }

    // remove barra inicial acidental
    final cleaned = raw.startsWith('/') ? raw.substring(1) : raw;

    // Se já tiver pasta gratis/ ou basico/, usa direto
    if (cleaned.startsWith('gratis/') || cleaned.startsWith('basico/')) {
      return [cleaned];
    }

    // Se vier só "arquivo.wav" (dado antigo), tenta gratis/ primeiro
    return ['gratis/$cleaned', cleaned];
  }

  Future<String> _resolvePlayableUrl(String urlOrPath) async {
    debugPrint('🎵 [AudioPlayerModal] resolve input="$urlOrPath"');

    final candidates = _candidateStorageKeys(urlOrPath);
    debugPrint('🎵 [AudioPlayerModal] candidates=${candidates.join(" | ")}');

    // URL antiga
    if (candidates.length == 1 &&
        (candidates.first.startsWith('http://') ||
            candidates.first.startsWith('https://'))) {
      debugPrint('🎵 [AudioPlayerModal] input já é URL HTTP');
      return candidates.first;
    }

    FirebaseException? lastFirebaseError;

    for (final key in candidates) {
      final cached = _urlCache[key];
      if (cached != null) {
        debugPrint('🎵 [AudioPlayerModal] cache HIT ($key) -> $cached');
        return cached;
      }

      try {
        final ref = FirebaseStorage.instance.ref(key);
        debugPrint('🎵 [AudioPlayerModal] trying ref.fullPath="${ref.fullPath}"');

        final downloadUrl = await ref.getDownloadURL();
        debugPrint('🎵 [AudioPlayerModal] downloadURL OK ($key) -> $downloadUrl');

        _urlCache[key] = downloadUrl;
        return downloadUrl;
      } on FirebaseException catch (e) {
        lastFirebaseError = e;
        debugPrint(
          '⚠️ [AudioPlayerModal] getDownloadURL falhou ($key): code=${e.code} message=${e.message}',
        );

        // se não encontrou, tenta próximo candidato
        if (e.code == 'object-not-found') {
          continue;
        }

        // permission/unauthorized: para aqui (não adianta tentar outro candidato)
        if (e.code == 'unauthorized' || e.code == 'permission-denied') {
          throw e;
        }

        // outros erros: tenta próximo mesmo assim
        continue;
      }
    }

    // Se chegou aqui, nenhum candidato funcionou
    if (lastFirebaseError != null) {
      throw lastFirebaseError;
    }

    throw Exception(
      'Não foi possível resolver URL tocável para "$urlOrPath".',
    );
  }

  Future<void> _init() async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🎵 [AudioPlayerModal] _init()');
    debugPrint('🎵 [AudioPlayerModal] audio.id="${widget.audio.id}"');
    debugPrint('🎵 [AudioPlayerModal] audio.title="${widget.audio.title}"');
    debugPrint('🎵 [AudioPlayerModal] audio.audioUrl/path="${widget.audio.audioUrl}"');

    try {
      final user = FirebaseAuth.instance.currentUser;
      debugPrint(
        '🔐 [AudioPlayerModal] currentUser uid=${user?.uid} email=${user?.email}',
      );

      if (user == null) {
        debugPrint('❌ [AudioPlayerModal] usuário não logado. Abortando.');
        return;
      }

      debugPrint('🔐 [AudioPlayerModal] checando canAccessAudio...');
      final canAccess = await _userService.canAccessAudio(audio: widget.audio);
      debugPrint('🔐 [AudioPlayerModal] canAccessAudio=$canAccess');

      if (!canAccess) {
        debugPrint('🚫 [AudioPlayerModal] sem acesso -> PremiumPage');
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumPage()),
        );
        return;
      }

      _attachListenersOnce();

      final sourceKey = widget.audio.audioUrl.trim();
      debugPrint('🎵 [AudioPlayerModal] sourceKey="$sourceKey"');

      debugPrint('🎵 [AudioPlayerModal] resolvendo URL tocável...');
      final playableUrl = await _resolvePlayableUrl(sourceKey);
      debugPrint('🎵 [AudioPlayerModal] playableUrl="$playableUrl"');

      // Evita tentar tocar "arquivo local" (FileDataSource)
      if (!(playableUrl.startsWith('http://') ||
          playableUrl.startsWith('https://'))) {
        debugPrint(
          '❌ [AudioPlayerModal] playableUrl NÃO é HTTP. Abortando.\nplayableUrl="$playableUrl"',
        );
        return;
      }

      debugPrint('🔁 [AudioPlayerModal] setUrl()');
      await _player.setUrl(playableUrl);

      await _player.setVolume(volume);

      if (mounted) {
        debugPrint('▶️ [AudioPlayerModal] play()');
        await _player.play();
        debugPrint('✅ [AudioPlayerModal] comando play enviado');
      }
    } on FirebaseException catch (e) {
      debugPrint(
        '❌ [AudioPlayerModal] FirebaseException: code=${e.code} message=${e.message}',
      );

      // Se o Storage negou (claims/regras), manda pra Premium
      if ((e.code == 'unauthorized' || e.code == 'permission-denied') &&
          mounted) {
        debugPrint('🚫 [AudioPlayerModal] Storage negou -> PremiumPage');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumPage()),
        );
      }
    } catch (e) {
      debugPrint('❌ [AudioPlayerModal] Erro no _init: $e');
    }
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 5),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Image.asset(
                    'assets/images/sonoramente_logo_branco.png',
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, _) {
                    return Transform.scale(
                      scale: _pulseController.value,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              appGreen.withValues(alpha: 0.65),
                              appGreen.withValues(alpha: 0.35),
                              appGreen.withValues(alpha: 0.15),
                            ],
                            stops: const [0.4, 0.7, 1],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.audio.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Slider(
                    activeColor: appGreen,
                    min: 0,
                    max: max(duration.inSeconds.toDouble(), 1),
                    value: position.inSeconds
                        .toDouble()
                        .clamp(0, duration.inSeconds.toDouble()),
                    onChanged: (v) {
                      _player.seek(Duration(seconds: v.toInt()));
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_format(position)),
                      Text(_format(duration)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  const Icon(Icons.volume_down),
                  Expanded(
                    child: Slider(
                      activeColor: appGreen,
                      min: 0,
                      max: 1,
                      value: volume,
                      onChanged: (v) {
                        setState(() => volume = v);
                        _player.setVolume(v);
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IconButton(
              iconSize: 64,
              color: appGreen,
              icon: Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
              ),
              onPressed: () {
                isPlaying ? _player.pause() : _player.play();
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_model.dart';

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

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  double volume = 1.0;

  late AnimationController _pulseController;

  static const Color appGreen = Color(0xFF8FB8A6);
  static const Color backgroundColor = Color(0xFFFBFAF7);

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

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.audio.audioUrl);
    } catch (_) {
      return;
    }

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

    await _player.setVolume(volume);
    if (mounted) {
      await _player.play();
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
                  builder: (_, __) {
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
                      _player.seek(
                        Duration(seconds: v.toInt()),
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
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
                isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
              ),
              onPressed: () {
                isPlaying
                    ? _player.pause()
                    : _player.play();
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

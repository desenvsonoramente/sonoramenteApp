import 'package:flutter/material.dart';
import '../config/mood_config.dart';

class MoodCard extends StatelessWidget {
  final String mood;
  final void Function(String mood) onTap;
  final int index;

  const MoodCard({
    super.key,
    required this.mood,
    required this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final config = moodConfig[mood];
    if (config == null) return const SizedBox();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 15 * (1 - value)),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () => onTap(mood),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFFEFE6D8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child:
                        Text(config.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      config.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Icon(Icons.chevron_right, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

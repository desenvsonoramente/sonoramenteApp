import 'package:flutter/material.dart';
import '../models/audio_model.dart';
import '../theme/category_colors.dart';

class AudioCard extends StatelessWidget {
  final AudioModel audio;
  final VoidCallback onTap;
  final bool isFavorite;

  const AudioCard({
    super.key,
    required this.audio,
    required this.onTap,
    this.isFavorite = false,
  });

  String formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return "1:00";
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return "$mins:${secs.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final colors = categoryColors[audio.category] ??
        [Colors.grey.shade200, Colors.grey.shade100];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha:0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow, size: 20, color: Colors.black54),
                ),
                if (isFavorite)
                  const Icon(Icons.favorite, size: 18, color: Color(0xFFC6B7D8)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              audio.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  formatDuration(audio.durationSeconds),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (audio.category.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text("•", style: TextStyle(color: Colors.black45)),
                  ),
                  Text(
                    audio.category,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ]
              ],
            )
          ],
        ),
      ),
    );
  }
}

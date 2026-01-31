import 'package:sonoramente/models/audio_model.dart';
import 'package:sonoramente/models/audio_history_model.dart';

class AudioHistoryItem {
  final AudioHistoryModel history;
  final AudioModel audio;

  AudioHistoryItem({
    required this.history,
    required this.audio,
  });
}

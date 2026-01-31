class AudioHistoryModel {
  final String audioId;
  final String userEmail;
  final DateTime listenedAt;
  final bool completed;

  AudioHistoryModel({
    required this.audioId,
    required this.userEmail,
    DateTime? listenedAt,
    this.completed = false,
  }) : listenedAt = listenedAt ?? DateTime.now();

  factory AudioHistoryModel.fromJson(Map<String, dynamic> json) {
    return AudioHistoryModel(
      audioId: json['audio_id'] as String,
      userEmail: json['user_email'] as String,
      listenedAt: json['listened_at'] != null
          ? DateTime.parse(json['listened_at'])
          : DateTime.now(),
      completed: json['completed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audio_id': audioId,
      'user_email': userEmail,
      'listened_at': listenedAt.toIso8601String(),
      'completed': completed,
    };
  }
}

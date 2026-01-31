class AudioHistory {
  final String id;
  final String audioId;
  final String userEmail;
  final DateTime playedAt;

  AudioHistory({
    required this.id,
    required this.audioId,
    required this.userEmail,
    required this.playedAt,
  });

  factory AudioHistory.fromJson(Map<String, dynamic> json) {
    return AudioHistory(
      id: json['id'].toString(),
      audioId: json['audio_id'],
      userEmail: json['user_email'],
      playedAt: DateTime.parse(json['played_at']),
    );
  }
}

class UserFavoriteModel {
  final String audioId;
  final String userEmail;

  UserFavoriteModel({
    required this.audioId,
    required this.userEmail,
  });

  factory UserFavoriteModel.fromJson(Map<String, dynamic> json) {
    return UserFavoriteModel(
      audioId: json['audio_id'],
      userEmail: json['user_email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audio_id': audioId,
      'user_email': userEmail,
    };
  }
}

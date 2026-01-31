class AudioModel {
  final String id;
  final String title;
  final String description;
  final String audioUrl;
  final String category;
  final String requiredBase; // gratis | basico
  final String requiredAddon; // maternidade | luto | etc (ou '')
  final int durationSeconds;

  AudioModel({
    required this.id,
    required this.title,
    required this.description,
    required this.audioUrl,
    required this.category,
    required this.requiredBase,
    required this.requiredAddon,
    required this.durationSeconds,
  });

  factory AudioModel.fromMap(String id, Map<String, dynamic> map) {
    return AudioModel(
      id: id,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      audioUrl: map['url'] ?? '',
      category: map['category'] ?? '',
      requiredBase: map['requiredBase'] ?? 'gratis',
      requiredAddon: map['requiredAddon'] ?? '',
      durationSeconds: map['duration_seconds'] ?? 0,
    );
  }
}

class AudioCategoryConfig {
  final String title;
  final String emoji;
  final int color; // ARGB

  const AudioCategoryConfig({
    required this.title,
    required this.emoji,
    required this.color,
  });
}

const Map<String, AudioCategoryConfig> audioCategories = {
  'antes_que_o_dia_comece': AudioCategoryConfig(
    title: 'Antes que o dia comece',
    emoji: '🌅',
    color: 0xFFA8C3B0,
  ),
  'ansiedade_acolhimento': AudioCategoryConfig(
    title: 'Ansiedade & Acolhimento',
    emoji: '🌿',
    color: 0xFFA8C3B0,
  ),
  'dias_dificeis': AudioCategoryConfig(
    title: 'Dias Difíceis',
    emoji: '🌧️',
    color: 0xFFA8A29E,
  ),
  'tristeza_melancolia': AudioCategoryConfig(
    title: 'Tristeza & Melancolia',
    emoji: '🌫️',
    color: 0xFF9CA3AF,
  ),
  'sono_desligamento': AudioCategoryConfig(
    title: 'Sono & Desligamento',
    emoji: '🌙',
    color: 0xFF6F8FAF,
  ),
  'sobrecarga_mental': AudioCategoryConfig(
    title: 'Sobrecarga Mental',
    emoji: '🧠',
    color: 0xFFCBD5E1,
  ),
  'limites_emocionais': AudioCategoryConfig(
    title: 'Limites Emocionais',
    emoji: '🛡️',
    color: 0xFF8B7355,
  ),
  'autocontrole_emocional': AudioCategoryConfig(
    title: 'Autocontrole Emocional',
    emoji: '🎭',
    color: 0xFF7B9FAB,
  ),
  'autocompaixao_autoestima': AudioCategoryConfig(
    title: 'Autocompaixão & Autoestima',
    emoji: '💛',
    color: 0xFFE8B4B8,
  ),
  'aceitacao_do_agora': AudioCategoryConfig(
    title: 'Aceitação do Agora',
    emoji: '🌱',
    color: 0xFFC6B7D8,
  ),
  'felicidade_leveza': AudioCategoryConfig(
    title: 'Felicidade & Leveza',
    emoji: '☀️',
    color: 0xFFF4D03F,
  ),
};

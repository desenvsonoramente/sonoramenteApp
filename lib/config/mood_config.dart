import 'package:flutter/material.dart';

class MoodConfig {
  final String emoji;
  final String title;
  final Color color;
  final List<Color> gradient;

  const MoodConfig({
    required this.emoji,
    required this.title,
    required this.color,
    required this.gradient,
  });
}

const Map<String, MoodConfig> moodConfig = {
  "antes_que_o_dia_comece": MoodConfig(
    emoji: "🌅",
    title: "Antes que o dia comece",
    color: Color(0xFFA8C3B0),
    gradient: [
      Color(0x33A8C3B0), // 20%
      Color(0x0DA8C3B0), // 5%
    ],
  ),
  "ansiedade_acolhimento": MoodConfig(
    emoji: "🌿",
    title: "Ansiedade & Acolhimento",
    color: Color(0xFFA8C3B0),
    gradient: [
      Color(0x33A8C3B0), // 20%
      Color(0x0DA8C3B0), // 5%
    ],
  ),
  "dias_dificeis": MoodConfig(
    emoji: "🌧️",
    title: "Dias Difíceis",
    color: Color(0xFFA8A29E),
    gradient: [
      Color(0x33A8A29E),
      Color(0x0DA8A29E),
    ],
  ),
  "tristeza_melancolia": MoodConfig(
    emoji: "🌫️",
    title: "Tristeza & Melancolia",
    color: Color(0xFF9CA3AF),
    gradient: [
      Color(0x339CA3AF),
      Color(0x0D9CA3AF),
    ],
  ),
  "sono_desligamento": MoodConfig(
    emoji: "🌙",
    title: "Sono & Desligamento",
    color: Color(0xFF6F8FAF),
    gradient: [
      Color(0x336F8FAF),
      Color(0x0D6F8FAF),
    ],
  ),
  "sobrecarga_mental": MoodConfig(
    emoji: "🧠",
    title: "Sobrecarga Mental",
    color: Color(0xFF64748B),
    gradient: [
      Color(0x3364748B),
      Color(0x0D64748B),
    ],
  ),
  "limites_emocionais": MoodConfig(
    emoji: "🛡️",
    title: "Limites Emocionais",
    color: Color(0xFF8B7355),
    gradient: [
      Color(0x338B7355),
      Color(0x0D8B7355),
    ],
  ),
  "autocontrole_emocional": MoodConfig(
    emoji: "⏳",
    title: "Autocontrole Emocional",
    color: Color(0xFF7B9FAB),
    gradient: [
      Color(0x337B9FAB),
      Color(0x0D7B9FAB),
    ],
  ),
  "autocompaixao_autoestima": MoodConfig(
    emoji: "💛",
    title: "Autocompaixão & Autoestima",
    color: Color(0xFFE8B4B8),
    gradient: [
      Color(0x33E8B4B8),
      Color(0x0DE8B4B8),
    ],
  ),
  "aceitacao_do_agora": MoodConfig(
    emoji: "🌱",
    title: "Aceitação do Agora",
    color: Color(0xFFC6B7D8),
    gradient: [
      Color(0x33C6B7D8),
      Color(0x0DC6B7D8),
    ],
  ),
  "felicidade_leveza": MoodConfig(
    emoji: "☀️",
    title: "Felicidade & Leveza",
    color: Color(0xFFF4D03F),
    gradient: [
      Color(0x33F4D03F),
      Color(0x0DF4D03F),
    ],
  ),
};

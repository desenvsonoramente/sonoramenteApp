import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? selectedMood;

  void handleMoodSelect(String mood) {
    setState(() {
      selectedMood = mood;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: selectedMood == null
            ? buildMoodSelection()
            : buildAudioList(),
      ),
    );
  }

  Widget buildMoodSelection() {
    final moods = [
      'ansiedade_acolhimento',
      'dias_dificeis',
      'tristeza_melancolia',
      'sono_desligamento',
      'sobrecarga_mental',
      'limites_emocionais',
      'autocontrole_emocional',
      'autocompaixao_autoestima',
      'meditacao_presenca',
      'felicidade_leveza',
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O que você precisa\nagora?',
            style: TextStyle(fontSize: 26),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              itemCount: moods.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final mood = moods[index];
                return GestureDetector(
                  onTap: () => handleMoodSelect(mood),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        mood.replaceAll('_', ' '),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAudioList() {
    return Column(
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              selectedMood = null;
            });
          },
          child: const Text('Voltar'),
        ),
        const Expanded(
          child: Center(child: Text('Lista de áudios aqui')),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

class Audio {
  final String id;
  final String title;
  final String category;
  final String? subcategory;
  final bool isPremium;

  Audio({
    required this.id,
    required this.title,
    required this.category,
    this.subcategory,
    this.isPremium = false,
  });
}

// Mock de áudios
final List<Audio> allAudios = [
  Audio(id: '1', title: 'Respirar fundo', category: 'ansiedade_acolhimento'),
  Audio(id: '2', title: 'Dormir bem', category: 'sono_desligamento'),
  Audio(id: '3', title: 'Meditar agora', category: 'meditacao_presenca'),
  Audio(id: '4', title: 'Autoestima leve', category: 'autocompaixao_autoestima', isPremium: true),
  Audio(id: '5', title: 'Dias difíceis', category: 'dias_dificeis'),
];

final Map<String, String> categoryLabels = {
  'all': 'Todos',
  'ansiedade_acolhimento': 'Ansiedade',
  'sono_desligamento': 'Sono',
  'meditacao_presenca': 'Meditação',
  'autocompaixao_autoestima': 'Autoestima',
  'felicidade_leveza': 'Felicidade',
  'sobrecarga_mental': 'Sobrecarga',
  'autocontrole_emocional': 'Autocontrole',
  'tristeza_melancolia': 'Tristeza',
  'autocuidado_real': 'Autocuidado',
  'dias_dificeis': 'Dias Difíceis',
};

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String selectedCategory = 'all';
  String searchQuery = '';
  Audio? currentAudio;
  final Set<String> favorites = {};

  List<Audio> get filteredAudios {
    return allAudios.where((audio) {
      final matchesCategory =
          selectedCategory == 'all' || audio.category == selectedCategory;
      final matchesSearch = searchQuery.isEmpty ||
          audio.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (audio.subcategory ?? '')
              .toLowerCase()
              .contains(searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void toggleFavorite(String id) {
    setState(() {
      favorites.contains(id) ? favorites.remove(id) : favorites.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: Column(
          children: [
            buildHeader(),
            buildSearch(),
            buildCategories(),
            Expanded(child: buildGrid()),
            if (currentAudio != null) buildPlayer(),
          ],
        ),
      ),
    );
  }

  Widget buildHeader() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Biblioteca',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('Todos os áudios disponíveis',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        onChanged: (v) => setState(() => searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Buscar áudios...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildCategories() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: categoryLabels.entries.map((entry) {
          final active = entry.key == selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: active,
              onSelected: (_) {
                setState(() => selectedCategory = entry.key);
              },
              selectedColor: const Color(0xFFA8C3B0),
              labelStyle: TextStyle(color: active ? Colors.white : Colors.black),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildGrid() {
    if (filteredAudios.isEmpty) {
      return const Center(child: Text('Nenhum áudio encontrado'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filteredAudios.length,
      itemBuilder: (context, index) {
        final audio = filteredAudios[index];
        final isFav = favorites.contains(audio.id);

        return GestureDetector(
          onTap: () => setState(() => currentAudio = audio),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      audio.title,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      audio.isPremium ? 'Premium' : 'Grátis',
                      style: TextStyle(
                          color:
                              audio.isPremium ? Colors.orange : Colors.green),
                    ),
                    IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : null,
                      ),
                      onPressed: () => toggleFavorite(audio.id),
                    )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildPlayer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              currentAudio!.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.pause),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => currentAudio = null),
          ),
        ],
      ),
    );
  }
}

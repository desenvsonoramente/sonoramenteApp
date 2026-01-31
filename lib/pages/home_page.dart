import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/audio_model.dart';
import '../config/mood_config.dart';
import '../pages/profile_page.dart';
import '../components/mood_card.dart';
import '../components/audio_player.dart';
import '../services/user_service.dart';
import '../pages/premium_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? selectedMood;

  final Color bgColor = const Color(0xFFA8C3B0);
  final Color boxColor = const Color(0xFFEFE6D8);

  User? user;
  final UserService _userService = UserService(); // mantido para canAccessAudio

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: _buildDrawer(),
      appBar: _buildTopBar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: selectedMood == null
                  ? _buildMoodList()
                  : _buildAudioList(),
            ),
          ],
        ),
      ),
    );
  }

  // ================= TOP BAR =================

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black),
        onPressed: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
    );
  }

  // ================= DRAWER =================

  Drawer _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: bgColor),
            accountName: Text(
              user?.displayName ?? 'Usuário',
              style: const TextStyle(color: Colors.black),
            ),
            accountEmail: Text(
              user?.email ?? '',
              style: const TextStyle(color: Colors.black87),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.black),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfilePage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }

  // ================= UI =================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 5),
      child: Center(
        child: Image.asset(
          'assets/images/sonoramente_logo.png',
          height: 200,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildMoodList() {
    final moods = moodConfig.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: moods.length,
      itemBuilder: (context, index) {
        final key = moods[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: MoodCard(
            mood: key,
            index: index,
            onTap: (mood) {
              setState(() {
                selectedMood = mood;
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildAudioList() {
    return Column(
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              selectedMood = null;
            });
          },
          child: const Text(
            'Voltar',
            style: TextStyle(color: Colors.black),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('audios')
                .where('category', isEqualTo: selectedMood)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final audios = snapshot.data!.docs
                  .map(
                    (d) => AudioModel.fromMap(
                      d.id,
                      d.data() as Map<String, dynamic>,
                    ),
                  )
                  .toList()
                ..sort((a, b) {
                  if (a.requiredBase == 'gratis' && b.requiredBase != 'gratis') return -1;
                  if (a.requiredBase != 'gratis' && b.requiredBase == 'gratis') return 1;
                  return 0;
                });

              return ListView.builder(
                itemCount: audios.length,
                itemBuilder: (context, index) {
                  final audio = audios[index];
                  final isFree = audio.requiredBase == 'gratis';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              audio.title,
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                          if (isFree)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'GRÁTIS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        audio.description,
                        style: const TextStyle(color: Colors.black),
                      ),
                      trailing: const Icon(Icons.play_arrow),
                      onTap: () async {
                        final canAccess = await _userService.canAccessAudio(isFreeAudio: isFree);

                        if (!mounted) return;

                        if (!canAccess) {
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PremiumPage()),
                          );
                          return;
                        }

                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => AudioPlayerModal(audio: audio),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

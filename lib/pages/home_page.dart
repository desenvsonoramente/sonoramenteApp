import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/mood_config.dart';
import '../components/mood_card.dart';
import '../pages/profile_page.dart';
import '../services/user_service.dart';
import 'audio_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Color bgColor = const Color(0xFFA8C3B0);

  final UserService _userService = UserService();
  User? user;

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
            Expanded(child: _buildMoodList()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: bgColor),
            accountName: Text(user?.displayName ?? 'Usuário', style: const TextStyle(color: Colors.black)),
            accountEmail: Text(user?.email ?? '', style: const TextStyle(color: Colors.black87)),
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              Navigator.pop(context);
              await _userService.signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Image.asset('assets/images/sonoramente_logo.png', height: 200, fit: BoxFit.contain),
    );
  }

  Widget _buildMoodList() {
    final moods = moodConfig.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: moods.length,
      itemBuilder: (context, index) {
        final mood = moods[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: MoodCard(
            mood: mood,
            index: index,
            onTap: (m) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AudioListPage(mood: m)));
            },
          ),
        );
      },
    );
  }
}

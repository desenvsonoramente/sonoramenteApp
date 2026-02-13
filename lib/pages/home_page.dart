import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/mood_config.dart';
import '../components/mood_card.dart';
import '../pages/profile_page.dart';
import '../pages/premium_page.dart';
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

  // ✅ Estado “inteligente” do plano (via claims)
  bool _claimsLoading = true;
  bool _sessionValid = false;
  String _basePlan = 'gratis'; // gratis | basico | premium (ou o que você usar)

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() => _claimsLoading = true);

    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        if (!mounted) return;
        setState(() {
          _sessionValid = false;
          _basePlan = 'gratis';
          _claimsLoading = false;
        });
        return;
      }

      // Pega claims do token (não precisa de context)
      final token = await u.getIdTokenResult();
      final claims = token.claims ?? {};

      final sessionValid = claims['sessionValid'] == true;
      final basePlan = (claims['basePlan'] as String?) ?? 'gratis';

      if (!mounted) return;
      setState(() {
        _sessionValid = sessionValid;
        _basePlan = basePlan;
        _claimsLoading = false;
      });
    } catch (_) {
      // Se der erro, assume não-premium (conservador)
      if (!mounted) return;
      setState(() {
        _sessionValid = false;
        _basePlan = 'gratis';
        _claimsLoading = false;
      });
    }
  }

  bool get _isPremium {
    // Ajuste se seus nomes de plano forem diferentes
    return _sessionValid && _basePlan != 'gratis';
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
      )
    );
  }

  Drawer _buildDrawer() {
    // Mostra “Seja Premium” somente se:
    // - claims já carregaram
    // - e o usuário NÃO é premium
    final showPremiumButton = !_claimsLoading && !_isPremium;

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

          if (showPremiumButton) ...[
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text('Seja Premium'),
              subtitle: const Text('Desbloqueie todos os áudios'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumPage()),
                ).then((_) {
                  // Quando voltar da tela Premium, atualiza claims
                  _loadClaims();
                });
              },
            ),
            const Divider(height: 1),
          ],

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
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
      child: Image.asset(
        'assets/images/sonoramente_logo.png',
        height: 200,
        fit: BoxFit.contain,
      ),
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AudioListPage(mood: m)),
              );
            },
          ),
        );
      },
    );
  }
}

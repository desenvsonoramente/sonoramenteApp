import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 🔐 Verifica se o usuário pode acessar um áudio
  Future<bool> canAccessAudio({required bool isFreeAudio}) async {
    if (isFreeAudio) return true;

    final user = _auth.currentUser;
    if (user == null) return false;

    final token = await user.getIdTokenResult();
    final sessionValid = token.claims?['sessionValid'];
    final basePlan = token.claims?['basePlan'];

    if (sessionValid != true) return false;
    if (basePlan == 'basico') return true;

    return false;
  }

  // Cria usuário no Firestore se não existir
  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'deviceId': deviceId,
        'plan': 'gratis',
        'addons': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }
}

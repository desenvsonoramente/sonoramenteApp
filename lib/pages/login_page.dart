import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/audio_model.dart';

class UserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ================= CREATE USER IF NOT EXISTS =================

  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = _firestore.collection("users").doc(user.uid);
    final snap = await doc.get();

    if (snap.exists) return;

    await doc.set({
      "uid": user.uid,
      "name": name,
      "email": email,
      "deviceId": deviceId,
      "createdAt": FieldValue.serverTimestamp(),
      "basePlan": "gratis", // gratis | basico
      "addons": [], // maternidade, luto, etc
    });
  }

  // ================= SIGN OUT =================

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ================= AUDIO ACCESS CHECK =================

  Future<bool> canAccessAudio(AudioModel audio) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc = await _firestore.collection("users").doc(user.uid).get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final base = data["basePlan"] ?? "gratis";
    final addons = List<String>.from(data["addons"] ?? []);

    // grátis não pode premium
    if (audio.requiredBase == "basico" && base != "basico") {
      return false;
    }

    // addon específico
    if (audio.requiredAddon.isNotEmpty && !addons.contains(audio.requiredAddon)) {
      return false;
    }

    return true;
  }

  // ================= DELETE ACCOUNT (PLAY STORE COMPLIANT) =================

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    print("🧠 DELETE_ACCOUNT -> UID: ${user.uid}");

    try {
      final callable = _functions.httpsCallable('deleteUserData');
      await callable();

      print("✅ DELETE_ACCOUNT -> Cloud Function OK");
    } catch (e) {
      print("❌ DELETE_ACCOUNT -> Cloud Function ERROR: $e");
      rethrow;
    }
  }
}

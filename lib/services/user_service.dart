import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/audio_model.dart';
import '../services/device_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Map<String, dynamic>? _cachedUser;
  DateTime? _fetchedAt;

  static const Duration _cacheTTL = Duration(minutes: 2);

  // =====================================================
  // ================== AUDIO ACCESS ======================
  // =====================================================

  Future<bool> canAccessAudio({required AudioModel audio}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    final userData = await _getUserData();
    if (userData == null) {
      return false;
    }

    final String plan = userData['plan'] ?? 'gratis';
    final List<String> addons =
        (userData['addons'] as List? ?? []).cast<String>();

    // 🔓 GRÁTIS
    if (audio.requiredBase == 'gratis') return true;

    // 🔒 DEVICE CHECK
    final String currentDeviceId = await DeviceService.getDeviceId();
    final String? deviceIdAtivo = userData['deviceIdAtivo'];

    if (deviceIdAtivo == null || deviceIdAtivo != currentDeviceId) {
      return false;
    }

    // 💎 PLANO BÁSICO
    if (audio.requiredBase == 'basico') {
      if (plan == 'gratis') {
        return false;
      }

      if (audio.requiredAddon.isEmpty) {
        return true;
      }

      if (addons.contains(audio.requiredAddon)) {
        return true;
      }

      return false;
    }

    return false;
  }

  // =====================================================
  // ================== USER CREATION =====================
  // =====================================================

  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    final user = _auth.currentUser;

    // 🔥 CRITICAL SECURITY CHECK
    if (user == null) {
      return;
    }

    // 🔐 PROTECT EMAIL LOGIN FLOW
    final providers = user.providerData.map((p) => p.providerId).toList();
    final isEmailPassword = providers.contains('password');

    // ⚠️ Se for email/password, só cria se displayName NÃO for vazio
    if (isEmailPassword && (name.isEmpty && user.displayName == null)) {
      return;
    }

    final uid = user.uid;
    final ref = _firestore.collection('users').doc(uid);

    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.exists) {
        return;
      }

      tx.set(ref, {
        'uid': uid,
        'name': name,
        'email': email,
        'plan': 'gratis',
        'addons': [],
        'deviceIdAtivo': deviceId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    clearCache();
  }

  // =====================================================
  // ================== LOGIN ÚNICO =======================
  // =====================================================

  /// ✅ Deve ser chamado SEMPRE após login (email ou google).
  /// Atualiza o deviceIdAtivo do usuário, garantindo "login único".
  Future<void> setActiveDevice({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    final uid = user.uid;
    final ref = _firestore.collection('users').doc(uid);

    await ref.set({
      'deviceIdAtivo': deviceId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    clearCache();
  }

  // =====================================================
  // ================== DELETE ACCOUNT ====================
  // =====================================================

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    // 🔹 Chama a Cloud Function segura que apaga Firestore e Auth
    final callable = _functions.httpsCallable('deleteAccount');
    await callable();
  }

  // =====================================================
  // ================== CACHE ==============================
  // =====================================================

  void clearCache() {
    _cachedUser = null;
    _fetchedAt = null;
  }

  // =====================================================
  // ================== SIGN OUT ===========================
  // =====================================================

  Future<void> signOut() async {
    clearCache();
    await _auth.signOut();
  }

  // =====================================================
  // ================== PUBLIC =============================
  // =====================================================

  Future<Map<String, dynamic>?> getUserData() async {
    return await _getUserData();
  }

  // =====================================================
  // ================== PRIVATE ============================
  // =====================================================

  Future<Map<String, dynamic>?> _getUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final uid = user.uid;

    if (_cachedUser != null &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < _cacheTTL) {
      return _cachedUser;
    }

    final snap = await _firestore.collection('users').doc(uid).get();
    if (!snap.exists) {
      return null;
    }

    _cachedUser = snap.data();
    _fetchedAt = DateTime.now();
    return _cachedUser;
  }
}

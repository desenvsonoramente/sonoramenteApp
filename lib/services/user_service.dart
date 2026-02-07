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
      print("❌ AUDIO_ACCESS -> NOT LOGGED");
      return false;
    }

    final userData = await _getUserData();
    if (userData == null) {
      print("❌ AUDIO_ACCESS -> USER DATA NULL");
      return false;
    }

    final String plan = userData['plan'] ?? 'gratis';
    final List<String> addons =
        (userData['addons'] as List? ?? []).cast<String>();

    print("🧠 AUDIO_ACCESS -> UID=${user.uid}");
    print("🧠 AUDIO_ACCESS -> PLAN=$plan");
    print("🧠 AUDIO_ACCESS -> ADDONS=$addons");
    print("🧠 AUDIO_ACCESS -> REQUIRED_BASE=${audio.requiredBase}");
    print("🧠 AUDIO_ACCESS -> REQUIRED_ADDON=${audio.requiredAddon}");

    // 🔓 GRÁTIS
    if (audio.requiredBase == 'gratis') return true;

    // 🔒 DEVICE CHECK
    final String currentDeviceId = await DeviceService.getDeviceId();
    final String? deviceIdAtivo = userData['deviceIdAtivo'];

    print("🧠 DEVICE CHECK -> CURRENT=$currentDeviceId | ACTIVE=$deviceIdAtivo");

    if (deviceIdAtivo == null || deviceIdAtivo != currentDeviceId) {
      print("❌ AUDIO_ACCESS -> DEVICE BLOCK");
      return false;
    }

    // 💎 PLANO BÁSICO
    if (audio.requiredBase == 'basico') {
      if (plan == 'gratis') {
        print("❌ AUDIO_ACCESS -> PLAN BLOCK");
        return false;
      }

      if (audio.requiredAddon.isEmpty) {
        print("✅ AUDIO_ACCESS -> BASIC OK");
        return true;
      }

      if (addons.contains(audio.requiredAddon)) {
        print("✅ AUDIO_ACCESS -> ADDON OK");
        return true;
      }

      print("❌ AUDIO_ACCESS -> ADDON BLOCK");
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
      print('❌ CREATE_USER -> NO AUTH USER');
      return;
    }

    // 🔐 PROTECT EMAIL LOGIN FLOW
    final providers = user.providerData.map((p) => p.providerId).toList();
    final isEmailPassword = providers.contains('password');

    print("🧠 CREATE_USER -> PROVIDERS=$providers");
    print("🧠 CREATE_USER -> NAME=$name EMAIL=$email");

    // ⚠️ Se for email/password, só cria se displayName NÃO for vazio
    if (isEmailPassword && (name.isEmpty && user.displayName == null)) {
      print('⚠️ CREATE_USER BLOCKED (email login without register)');
      return;
    }

    final uid = user.uid;
    final ref = _firestore.collection('users').doc(uid);

    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.exists) {
        print("🧠 CREATE_USER -> ALREADY EXISTS");
        return;
      }

      print("🔥 CREATE_USER -> CREATING FIRESTORE DOC");

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
  // ================== DELETE ACCOUNT ====================
  // =====================================================

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      print("❌ DELETE_ACCOUNT -> NO USER");
      return;
    }

    print("🧠 DELETE_ACCOUNT -> UID=${user.uid}");

    try {
      final callable = _functions.httpsCallable('deleteUserData');
      await callable();

      print("✅ DELETE_ACCOUNT -> CLOUD FUNCTION OK");
    } catch (e) {
      print("❌ DELETE_ACCOUNT -> CLOUD FUNCTION ERROR: $e");
      rethrow;
    }
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
    print("🧠 SIGN_OUT");
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
      print("🧠 USER CACHE HIT");
      return _cachedUser;
    }

    print("🧠 USER CACHE MISS -> FIRESTORE GET");

    final snap = await _firestore.collection('users').doc(uid).get();
    if (!snap.exists) {
      print("❌ USER DOC NOT FOUND IN FIRESTORE");
      return null;
    }

    _cachedUser = snap.data();
    _fetchedAt = DateTime.now();
    return _cachedUser;
  }
}

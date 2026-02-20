import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/audio_model.dart';
import '../services/device_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ Use a mesma região das suas functions
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Map<String, dynamic>? _cachedUser;
  DateTime? _fetchedAt;

  static const Duration _cacheTTL = Duration(minutes: 2);

  // =====================================================
  // ================== AUDIO ACCESS ======================
  // =====================================================

  Future<bool> canAccessAudio({required AudioModel audio}) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // 🔓 Áudio grátis é sempre liberado
    if (audio.requiredBase == 'gratis') return true;

    // ✅ Fonte de verdade do plano/sessão: Custom Claims (anti-fraude)
    final claims = await _getClaimsSafe();
    final bool sessionValid = claims['sessionValid'] == true;

    // Se você usar "basePlan" (recomendado)
    final String basePlan = (claims['basePlan'] as String?) ?? 'gratis';

    // Addons em claims (se você usar)
    final List<String> claimAddons =
        (claims['addons'] as List? ?? const []).cast<String>();

    if (!sessionValid) return false;

    // 🔒 DEVICE CHECK (login único)
    // DeviceIdAtivo está no Firestore (controle do seu app)
    final userData = await _getUserDataSafe();
    if (userData == null) return false;

    final String currentDeviceId = await DeviceService.getDeviceId();
    final String? deviceIdAtivo = userData['deviceIdAtivo'] as String?;

    if (deviceIdAtivo == null || deviceIdAtivo != currentDeviceId) {
      return false;
    }

    // 💎 Conteúdo "basico"
    if (audio.requiredBase == 'basico') {
      if (basePlan == 'gratis') return false;

      if (audio.requiredAddon.isEmpty) return true;

      // Se você usa addons por módulo
      final String requiredAddon = audio.requiredAddon;
      if (requiredAddon.isEmpty) return true;

      // tenta claims primeiro, e como fallback usa Firestore
      if (claimAddons.contains(requiredAddon)) return true;

      final List<String> dbAddons =
          (userData['addons'] as List? ?? const []).cast<String>();
      if (dbAddons.contains(requiredAddon)) return true;

      return false;
    }

    // Outros níveis (se adicionar no futuro)
    return false;
  }

  // =====================================================
  // ================== USER CREATION =====================
  // =====================================================
  // ✅ Produção definitiva: userDoc é criado no BACKEND (Auth Trigger).
  // Deixei o método para compatibilidade, mas ele não cria mais nada.
  // Se você preferir, pode remover as chamadas no app.
  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    // No-op por design (backend cuida disso).
    // Ainda assim, garantimos deviceIdAtivo após login:
    await setActiveDevice(deviceId: deviceId);
  }

  // =====================================================
  // ================== LOGIN ÚNICO =======================
  // =====================================================

  /// ✅ Chame após login (email ou google).
  /// Atualiza o deviceIdAtivo do usuário.
  Future<void> setActiveDevice({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final ref = _firestore.collection('users').doc(uid);

    try {
      await ref.set({
        'deviceIdAtivo': deviceId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // Se App Check estiver exigindo e falhar, não crasha o app.
      if (e.code == 'permission-denied') {
        // Não dá pra gravar deviceIdAtivo => por segurança, não libera conteúdo.
        // Apenas limpa cache para que próxima tentativa tente de novo.
        clearCache();
        return;
      }
      rethrow;
    }

    clearCache();
  }

  // =====================================================
  // ================== DELETE ACCOUNT ====================
  // =====================================================

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final callable = _functions.httpsCallable('deleteAccount');
      await callable();
      await signOut();
    } on FirebaseFunctionsException catch (e) {
      // Repassa uma exceção com mensagem “user friendly”
      final msg = (e.message == null || e.message!.isEmpty)
          ? 'Não foi possível excluir sua conta agora. Tente novamente.'
          : e.message!;
      throw Exception(msg);
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
    clearCache();
    await _auth.signOut();
  }

  // =====================================================
  // ================== PUBLIC =============================
  // =====================================================

  Future<Map<String, dynamic>?> getUserData() async {
    return await _getUserDataSafe();
  }

  /// ✅ Força refresh de claims (use após compra/restore se quiser)
  Future<Map<String, dynamic>> refreshClaims() async {
    final user = _auth.currentUser;
    if (user == null) return {};
    await user.getIdToken(true);
    final token = await user.getIdTokenResult(true);
    return token.claims ?? {};
  }

  // =====================================================
  // ================== PRIVATE ============================
  // =====================================================

  Future<Map<String, dynamic>> _getClaimsSafe() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    try {
      // Não força refresh sempre (performance). Quando compra, você chama refresh.
      final token = await user.getIdTokenResult();
      return token.claims ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> _getUserDataSafe() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    if (_cachedUser != null &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < _cacheTTL) {
      return _cachedUser;
    }

    final uid = user.uid;

    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!snap.exists) return null;

      _cachedUser = snap.data();
      _fetchedAt = DateTime.now();
      return _cachedUser;
    } on FirebaseException catch (e) {
      // Produção: não crasha por App Check/permissão
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }
}
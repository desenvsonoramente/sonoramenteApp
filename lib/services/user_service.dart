import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/audio_model.dart';
import '../services/device_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ Sempre amarra no Firebase.app() + mesma região das functions deployadas
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    app: Firebase.app(),
    region: 'us-central1',
  );

  Map<String, dynamic>? _cachedUser;
  DateTime? _fetchedAt;

  static const Duration _cacheTTL = Duration(minutes: 2);

  // ✅ Cache do deviceId (evita chamadas repetidas e inconsistência)
  String? _cachedDeviceId;
  Future<String>? _deviceIdInFlight;

  Future<String> _getDeviceIdCached() async {
    final c = _cachedDeviceId;
    if (c != null && c.isNotEmpty) return c;

    _deviceIdInFlight ??= DeviceService.getDeviceId();
    final id = await _deviceIdInFlight!;
    _cachedDeviceId = id;
    _deviceIdInFlight = null;

    return id;
  }

  // =====================================================
  // ================== AUDIO ACCESS ======================
  // =====================================================

  /// REGRA DE NEGÓCIO:
  /// - basePlan: 'gratis' | 'basico'
  /// - addons: lista de pacotes (ex: 'maternidade', 'luto', ...)
  ///
  /// AudioModel:
  /// - requiredBase: 'gratis' | 'basico'
  /// - requiredAddon: '' | 'maternidade' | 'luto' | etc
  ///
  /// Liberação:
  /// - requiredBase == 'gratis' => libera
  /// - requiredBase == 'basico' => exige sessionValid + basePlan=='basico'
  ///    - requiredAddon vazio => libera
  ///    - requiredAddon preenchido => exige addon
  Future<bool> canAccessAudio({required AudioModel audio}) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // 🔓 Conteúdo grátis: sempre libera
    if (audio.requiredBase == 'gratis') return true;

    // ✅ Para qualquer coisa além de gratis:
    // exige claims válidas + basePlan basico
    final claims = await _getClaimsSafe();
    final bool sessionValid = claims['sessionValid'] == true;
    final String basePlan = (claims['basePlan'] as String?) ?? 'gratis';
    final List<String> claimAddons =
        (claims['addons'] as List? ?? const []).cast<String>();

    if (!sessionValid) return false;
    if (basePlan != 'basico') return false;

    // 🔒 DEVICE CHECK (login único) — exige deviceIdAtivo == deviceId local
    final userData = await _getUserDataSafe();
    if (userData == null) return false;

    final String currentDeviceId = await _getDeviceIdCached();
    final String? deviceIdAtivo = (userData['deviceIdAtivo'] as String?)?.trim();

    if (deviceIdAtivo == null || deviceIdAtivo.isEmpty) return false;
    if (deviceIdAtivo != currentDeviceId) return false;

    // Se não for explicitamente 'basico', bloqueia por padrão (conservador)
    if (audio.requiredBase != 'basico') return false;

    // ✅ Conteúdo base do plano (sem addon)
    final String requiredAddon = audio.requiredAddon.trim();
    if (requiredAddon.isEmpty) return true;

    // ✅ Conteúdo de pacote: precisa do addon
    if (claimAddons.contains(requiredAddon)) return true;

    // Fallback no Firestore (caso claims ainda não propagaram)
    final List<String> dbAddons =
        (userData['addons'] as List? ?? const []).cast<String>();
    if (dbAddons.contains(requiredAddon)) return true;

    return false;
  }

  // =====================================================
  // ================== USER CREATION =====================
  // =====================================================
  // ✅ Produção definitiva: userDoc é criado no BACKEND (Auth Trigger).
  // Mantido para compatibilidade: só garante deviceIdAtivo após login.
  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    await setActiveDevice(deviceId: deviceId);
  }

  // =====================================================
  // ================== LOGIN ÚNICO =======================
  // =====================================================

  /// ✅ Chame após login (email ou google).
  /// Atualiza o deviceIdAtivo do usuário via BACKEND.
  Future<void> setActiveDevice({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Atualiza cache local também
    _cachedDeviceId = deviceId;

    try {
      final callable = _functions.httpsCallable(
        'setActiveDevice',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call(<String, dynamic>{
        'deviceId': deviceId,
      });
    } on FirebaseFunctionsException {
      clearCache();
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
      final callable = _functions.httpsCallable(
        'deleteAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      await callable.call();
      await signOut();
    } on FirebaseFunctionsException catch (e) {
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
    _cachedDeviceId = null;
    _deviceIdInFlight = null;
    await _auth.signOut();
  }

  // =====================================================
  // ================== PUBLIC =============================
  // =====================================================

  Future<Map<String, dynamic>?> getUserData() async {
    return _getUserDataSafe();
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
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }
}
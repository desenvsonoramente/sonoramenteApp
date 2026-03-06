import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/audio_model.dart';
import '../services/device_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    app: Firebase.app(),
    region: 'us-central1',
  );

  Map<String, dynamic>? _cachedUser;
  DateTime? _fetchedAt;

  static const Duration _cacheTTL = Duration(minutes: 2);

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

  HttpsCallable _callable(String name) {
    return _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
  }

  Future<bool> canAccessAudio({required AudioModel audio}) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    if (audio.requiredBase == 'gratis') return true;

    final claims = await _getClaimsSafe();
    final bool sessionValid = claims['sessionValid'] == true;
    final String basePlan = (claims['basePlan'] as String?) ?? 'gratis';
    final List<String> claimAddons =
        (claims['addons'] as List? ?? const []).cast<String>();

    if (!sessionValid) return false;
    if (basePlan != 'basico') return false;

    final userData = await _getUserDataSafe();
    if (userData == null) return false;

    final String currentDeviceId = await _getDeviceIdCached();
    final String deviceIdAtivo =
        (userData['deviceIdAtivo'] as String?)?.trim() ?? '';

    if (deviceIdAtivo.isEmpty) return false;
    if (deviceIdAtivo != currentDeviceId) return false;

    if (audio.requiredBase != 'basico') return false;

    final String requiredAddon = audio.requiredAddon.trim();
    if (requiredAddon.isEmpty) return true;

    if (claimAddons.contains(requiredAddon)) return true;

    final List<String> dbAddons =
        (userData['addons'] as List? ?? const []).cast<String>();
    if (dbAddons.contains(requiredAddon)) return true;

    return false;
  }

  Future<void> createUserIfNotExists({
    required String name,
    required String email,
    required String deviceId,
  }) async {
    await setActiveDevice(deviceId: deviceId);
  }

  Future<void> setActiveDevice({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    _cachedDeviceId = deviceId;

    await _callable('setActiveDevice').call({
      'deviceId': deviceId,
    });

    clearCache();
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _callable('deleteAccount').call();
      await signOut();
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message == null || e.message!.isEmpty)
          ? 'Não foi possível excluir sua conta agora. Tente novamente.'
          : e.message!;
      throw Exception(msg);
    }
  }

  void clearCache() {
    _cachedUser = null;
    _fetchedAt = null;
  }

  Future<void> signOut() async {
    clearCache();
    _cachedDeviceId = null;
    _deviceIdInFlight = null;

    try {
      final isSignedInWithGoogle = await _googleSignIn.isSignedIn();
      if (isSignedInWithGoogle) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}

    try {
      await _auth.signOut();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserData() async {
    return _getUserDataSafe();
  }

  Future<Map<String, dynamic>> refreshClaims() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    await user.getIdToken(true);
    final token = await user.getIdTokenResult(true);
    clearCache();
    return token.claims ?? {};
  }

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

    try {
      final result = await _callable('getUserProfile').call();
      final data = Map<String, dynamic>.from(
        (result.data as Map?) ?? const {},
      );

      if (data.isEmpty) return null;

      _cachedUser = data;
      _fetchedAt = DateTime.now();
      return _cachedUser;
    } on FirebaseFunctionsException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
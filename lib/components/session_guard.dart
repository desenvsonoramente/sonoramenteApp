import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/device_service.dart';

class SessionGuard extends StatefulWidget {
  final Widget child;

  const SessionGuard({
    super.key,
    required this.child,
  });

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  Future<String>? _deviceIdFuture;
  String? _deviceId;

  bool _kicked = false;

  // Grace period após login
  Timer? _armTimer;
  bool _armed = false;
  String? _armedUid;

  // Evita múltiplas confirmações simultâneas
  bool _confirming = false;

  static const Duration _graceAfterLogin = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _deviceIdFuture = DeviceService.getDeviceId();
    _listenAuth();
  }

  void _listenAuth() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _userSub?.cancel();
      _userSub = null;

      _armTimer?.cancel();
      _armed = false;
      _armedUid = null;
      _confirming = false;

      // Reset quando desloga
      if (user == null) {
        _kicked = false;
        return;
      }

      // Obtém deviceId uma única vez
      try {
        _deviceId ??= await _deviceIdFuture!;
      } catch (_) {
        return;
      }

      // Grace period: não derruba logo após login
      _armedUid = user.uid;
      _armTimer = Timer(_graceAfterLogin, () {
        if (!mounted) return;
        final current = FirebaseAuth.instance.currentUser;
        if (current?.uid == _armedUid) {
          _armed = true;
        }
      });

      final ref =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      _userSub = ref.snapshots(
        includeMetadataChanges: true,
      ).listen(
        (snap) async {
          // Se doc ainda não existe, não derruba
          if (!snap.exists) return;

          final data = snap.data();
          if (data == null) return;

          final active = (data['deviceIdAtivo'] ?? '').toString();
          final current = _deviceId ?? '';

          if (active.isEmpty || current.isEmpty) return;

          // Durante grace period, não chuta
          if (!_armed) return;

          // Ignora cache / pending writes
          if (snap.metadata.isFromCache) return;
          if (snap.metadata.hasPendingWrites) return;

          // Confirma no servidor antes de chutar
          if (active != current) {
            await _confirmAndMaybeKick(
              ref: ref,
              message: 'Sua conta foi acessada em outro dispositivo.',
            );
          }
        },
      );
    });
  }

  Future<void> _confirmAndMaybeKick({
    required DocumentReference<Map<String, dynamic>> ref,
    required String message,
  }) async {
    if (_kicked) return;
    if (_confirming) return;
    _confirming = true;

    try {
      final serverSnap =
          await ref.get(const GetOptions(source: Source.server));
      if (!serverSnap.exists) return;

      final data = serverSnap.data();
      if (data == null) return;

      final active = (data['deviceIdAtivo'] ?? '').toString();
      final current = _deviceId ?? '';

      if (active.isEmpty || current.isEmpty) return;

      if (active != current) {
        await _kickToLogin(message: message);
      }
    } catch (_) {
      // Silencioso por segurança (evita falsos positivos)
    } finally {
      _confirming = false;
    }
  }

  Future<void> _kickToLogin({required String message}) async {
    if (_kicked) return;
    _kicked = true;

    try {
      await _userSub?.cancel();
      _userSub = null;
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _userSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

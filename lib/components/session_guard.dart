import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/device_service.dart';
import '../services/purchase_guard.dart';

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
  static const String _tag = 'SessionGuard';

  void _log(String msg) {
    // ignore: avoid_print
    print('🛡️ [$_tag] $msg');
  }

  void _warn(String msg) {
    // ignore: avoid_print
    print('⚠️ [$_tag] $msg');
  }

  void _err(String msg) {
    // ignore: avoid_print
    print('❌ [$_tag] $msg');
  }

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

  // ✅ Aumentado: 4s era pouco para latência/cache/createUserIfNotExists + setActiveDevice
  static const Duration _graceAfterLogin = Duration(seconds: 8);

  // ✅ Controla lock/unlock (compra/restore) para evitar signOut no meio do fluxo
  final PurchaseGuard _purchaseGuard = PurchaseGuard.instance;

  // ✅ Se detectar mismatch durante PurchaseGuard LOCKED, confirma quando destravar
  bool _pendingMismatch = false;
  DocumentReference<Map<String, dynamic>>? _pendingRef;
  String _pendingMessage = 'Sua conta foi acessada em outro dispositivo.';

  Timer? _pendingDebounce;

  @override
  void initState() {
    super.initState();
    _log('initState()');

    _deviceIdFuture = DeviceService.getDeviceId();

    // ✅ Quando destravar, se tinha mismatch pendente, confirma no servidor
    _purchaseGuard.listenable.addListener(_onPurchaseGuardChanged);

    _listenAuth();
  }

  void _clearPendingMismatch([String reason = '']) {
    if (_pendingMismatch || _pendingRef != null) {
      _log('clear pending mismatch | reason=$reason');
    }
    _pendingMismatch = false;
    _pendingRef = null;
    _pendingMessage = 'Sua conta foi acessada em outro dispositivo.';
  }

  void _onPurchaseGuardChanged() {
    final locked = _purchaseGuard.isLocked;
    _log('PurchaseGuard changed | locked=$locked pendingMismatch=$_pendingMismatch');

    if (!locked && _pendingMismatch) {
      _schedulePendingConfirm(reason: 'purchaseGuard unlocked');
    }
  }

  void _schedulePendingConfirm({required String reason}) {
    if (_kicked) {
      _log('_schedulePendingConfirm() skip | already kicked');
      return;
    }
    if (_confirming) {
      _log('_schedulePendingConfirm() skip | confirming already in progress');
      return;
    }
    if (_purchaseGuard.isLocked) {
      _warn('_schedulePendingConfirm() blocked | still locked');
      return;
    }

    final ref = _pendingRef;
    if (ref == null) {
      _warn('_schedulePendingConfirm() no pendingRef -> clear pending');
      _clearPendingMismatch('pendingRef null');
      return;
    }

    _pendingDebounce?.cancel();
    _pendingDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;

      // Se durante o debounce travou de novo, segura
      if (_purchaseGuard.isLocked) {
        _warn('pending confirm debounce fired but LOCKED again -> keep pending');
        return;
      }

      _log('pending confirm firing | reason=$reason path=${ref.path}');
      await _confirmAndMaybeKick(ref: ref, message: _pendingMessage);
    });
  }

  void _resetForUserNull() {
    _log('_resetForUserNull()');
    _kicked = false;

    _armTimer?.cancel();
    _armTimer = null;

    _armed = false;
    _armedUid = null;

    _confirming = false;

    _pendingDebounce?.cancel();
    _pendingDebounce = null;

    _clearPendingMismatch('user null');
  }

  Future<void> _cancelUserSub(String reason) async {
    try {
      if (_userSub != null) {
        _log('_cancelUserSub() | reason=$reason');
        await _userSub?.cancel();
      }
    } catch (e) {
      _warn('_cancelUserSub() error | reason=$reason | $e');
    } finally {
      _userSub = null;
    }
  }

  void _listenAuth() {
    _log('_listenAuth() start');

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _log('authStateChanges() | user=${user?.uid ?? '(null)'}');

      await _cancelUserSub('authStateChanges new user');

      _armTimer?.cancel();
      _armTimer = null;

      _armed = false;
      _armedUid = null;

      _confirming = false;

      _pendingDebounce?.cancel();
      _pendingDebounce = null;
      _clearPendingMismatch('auth changed');

      // Reset quando desloga
      if (user == null) {
        _resetForUserNull();
        return;
      }

      // Obtém deviceId uma única vez
      try {
        if (_deviceId == null || _deviceId!.isEmpty) {
          _log('deviceId resolving...');
          _deviceId ??= await (_deviceIdFuture ?? DeviceService.getDeviceId());
          _log('deviceId ok | deviceId=$_deviceId');
        } else {
          _log('deviceId cached | deviceId=$_deviceId');
        }
      } catch (e) {
        _err('deviceId error | $e');
        return;
      }

      // Grace period: não derruba logo após login
      _armedUid = user.uid;
      _log('arming started | uid=$_armedUid grace=${_graceAfterLogin.inSeconds}s');

      _armTimer = Timer(_graceAfterLogin, () {
        if (!mounted) return;
        final current = FirebaseAuth.instance.currentUser;
        if (current?.uid == _armedUid) {
          _armed = true;
          _log('armed=true | uid=$_armedUid');
        } else {
          _warn('arm skipped | currentUid=${current?.uid} armedUid=$_armedUid');
        }
      });

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

      _log('subscribing user doc snapshots | path=${ref.path}');

      _userSub = ref
          .snapshots(includeMetadataChanges: true)
          .listen((snap) async {
        final uidNow = FirebaseAuth.instance.currentUser?.uid;

        _log(
          'snapshot | exists=${snap.exists} fromCache=${snap.metadata.isFromCache} '
          'pendingWrites=${snap.metadata.hasPendingWrites} authUid=$uidNow armed=$_armed locked=${_purchaseGuard.isLocked}',
        );

        // Se auth mudou, não toma ação com snapshot antigo
        if (uidNow == null || uidNow != _armedUid) {
          _warn('snapshot: auth uid changed -> ignore | uidNow=$uidNow armedUid=$_armedUid');
          return;
        }

        // Se doc ainda não existe, não derruba
        if (!snap.exists) {
          _clearPendingMismatch('doc not exists');
          _log('snapshot: doc does not exist yet -> ignore');
          return;
        }

        final data = snap.data();
        if (data == null) {
          _warn('snapshot: data=null -> ignore');
          return;
        }

        final active = (data['deviceIdAtivo'] ?? '').toString();
        final current = (_deviceId ?? '').toString();

        _log('snapshot: deviceIdAtivo="$active" currentDevice="$current"');

        if (active.isEmpty || current.isEmpty) {
          _log('snapshot: active/current empty -> ignore');
          return;
        }

        // Durante grace period, não chuta
        if (!_armed) {
          _log('snapshot: not armed yet -> ignore');
          return;
        }

        // Ignora cache / pending writes
        if (snap.metadata.isFromCache) {
          _log('snapshot: isFromCache -> ignore');
          return;
        }
        if (snap.metadata.hasPendingWrites) {
          _log('snapshot: hasPendingWrites -> ignore');
          return;
        }

        // Se mismatch...
        if (active != current) {
          _warn('snapshot mismatch detected | active="$active" current="$current"');

          // ✅ Se compra/restore em andamento: NÃO chuta, marca pendente e confirma quando destravar
          if (_purchaseGuard.isLocked) {
            _warn('snapshot: PurchaseGuard LOCKED -> mark pending mismatch');
            _pendingMismatch = true;
            _pendingRef = ref;
            _pendingMessage = 'Sua conta foi acessada em outro dispositivo.';
            return;
          }

          // Confirma no servidor antes de chutar
          await _confirmAndMaybeKick(
            ref: ref,
            message: 'Sua conta foi acessada em outro dispositivo.',
          );
        } else {
          _clearPendingMismatch('snapshot match');
          _log('snapshot match | OK');
        }
      }, onError: (e) {
        _err('user snapshots onError | $e');
      });
    }, onError: (e) {
      _err('authStateChanges onError | $e');
    });
  }

  Future<void> _confirmAndMaybeKick({
    required DocumentReference<Map<String, dynamic>> ref,
    required String message,
  }) async {
    if (_kicked) {
      _log('_confirmAndMaybeKick() skip | already kicked');
      return;
    }
    if (_confirming) {
      _log('_confirmAndMaybeKick() skip | confirming already in progress');
      return;
    }

    // ✅ Se compra/restore em andamento, adia
    if (_purchaseGuard.isLocked) {
      _warn('_confirmAndMaybeKick() blocked | PurchaseGuard LOCKED -> keep pending');
      _pendingMismatch = true;
      _pendingRef = ref;
      _pendingMessage = message;
      return;
    }

    _confirming = true;
    _log('_confirmAndMaybeKick() start | path=${ref.path}');

    try {
      final uidNowStart = FirebaseAuth.instance.currentUser?.uid;
      if (uidNowStart == null || uidNowStart != _armedUid) {
        _warn('confirm: auth uid changed before server get -> ignore');
        return;
      }

      final serverSnap = await ref.get(const GetOptions(source: Source.server));
      _log('server get done | exists=${serverSnap.exists}');

      if (!serverSnap.exists) {
        _clearPendingMismatch('server doc not exists');
        _log('server: doc not exists -> ignore');
        return;
      }

      final data = serverSnap.data();
      if (data == null) {
        _warn('server: data=null -> ignore');
        return;
      }

      final active = (data['deviceIdAtivo'] ?? '').toString();
      final current = (_deviceId ?? '').toString();
      final uidNow = FirebaseAuth.instance.currentUser?.uid;

      _log(
        'server: deviceIdAtivo="$active" currentDevice="$current" authUid=$uidNow armedUid=$_armedUid locked=${_purchaseGuard.isLocked}',
      );

      if (active.isEmpty || current.isEmpty) {
        _log('server: active/current empty -> ignore');
        return;
      }

      if (uidNow == null || uidNow != _armedUid) {
        _warn('server: auth uid changed -> ignore | uidNow=$uidNow armedUid=$_armedUid');
        return;
      }

      // ✅ Checagem final antes de chutar
      if (_purchaseGuard.isLocked) {
        _warn('server: PurchaseGuard LOCKED (late) -> keep pending');
        _pendingMismatch = true;
        _pendingRef = ref;
        _pendingMessage = message;
        return;
      }

      if (active != current) {
        _warn('server mismatch CONFIRMED -> kick | active="$active" current="$current"');
        await _kickToLogin(message: message);
      } else {
        _clearPendingMismatch('server match');
        _log('server match -> no kick');
      }
    } on FirebaseException catch (e) {
      _err('_confirmAndMaybeKick() FirebaseException | code=${e.code} msg=${e.message}');
      // ✅ Se falhou por rede/unavailable, não chuta: mantém pending pra tentar depois
      if (!_kicked) {
        _pendingMismatch = true;
        _pendingRef = ref;
        _pendingMessage = message;
      }
    } catch (e) {
      _err('_confirmAndMaybeKick() error | $e');
      if (!_kicked) {
        _pendingMismatch = true;
        _pendingRef = ref;
        _pendingMessage = message;
      }
    } finally {
      _confirming = false;
      _log('_confirmAndMaybeKick() end');
    }
  }

  Future<void> _kickToLogin({required String message}) async {
    if (_kicked) {
      _log('_kickToLogin() skip | already kicked');
      return;
    }

    // ✅ Nunca chuta durante compra/restore
    if (_purchaseGuard.isLocked) {
      _warn('_kickToLogin() blocked | PurchaseGuard LOCKED -> keep pending');
      _pendingMismatch = true;
      _pendingMessage = message;
      return;
    }

    _kicked = true;
    _warn('_kickToLogin() EXECUTING | message="$message"');

    _pendingDebounce?.cancel();
    _pendingDebounce = null;

    await _cancelUserSub('kickToLogin');

    try {
      _log('_kickToLogin() signing out...');
      await FirebaseAuth.instance.signOut();
      _log('_kickToLogin() signOut ok');
    } catch (e) {
      _err('_kickToLogin() signOut error | $e');
    }

    if (!mounted) {
      _warn('_kickToLogin() not mounted -> skip snackbar');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      _log('_kickToLogin() snackbar shown');
    } else {
      _warn('_kickToLogin() messenger null -> no snackbar');
    }
  }

  @override
  void dispose() {
    _log('dispose()');

    _purchaseGuard.listenable.removeListener(_onPurchaseGuardChanged);

    _pendingDebounce?.cancel();
    _pendingDebounce = null;

    _armTimer?.cancel();
    _armTimer = null;

    _userSub?.cancel();
    _userSub = null;

    _authSub?.cancel();
    _authSub = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
import 'dart:async';
import 'package:flutter/foundation.dart';

class PurchaseGuard {
  PurchaseGuard._();
  static final PurchaseGuard instance = PurchaseGuard._();

  /// 🔒 Locks por "token" (motivo/escopo) pra evitar unlock errado
  final Set<String> _locks = <String>{};

  /// ✅ Para AuthGate com ValueListenableBuilder
  final ValueNotifier<int> _lockCount = ValueNotifier<int>(0);

  /// 🔁 Mantemos stream por compatibilidade com código antigo
  final StreamController<bool> _ctrl = StreamController<bool>.broadcast();

  ValueListenable<int> get listenable => _lockCount;

  bool get isLocked => _lockCount.value > 0;

  Stream<bool> get stream => _ctrl.stream;

  List<String> get activeLocks => List.unmodifiable(_locks);

  /// Gera um token único quando não vem reason
  String _token(String? reason) {
    final r = (reason ?? '').trim();
    if (r.isNotEmpty) return r;
    // token fallback: evita colisão em chamadas sem reason
    return 'lock@${DateTime.now().microsecondsSinceEpoch}';
  }

  /// 🔐 Entra em modo protegido
  /// Retorna o token do lock para desbloquear o MESMO lock depois.
  String lock({String? reason}) {
    final t = _token(reason);

    final added = _locks.add(t);
    if (!added) {
      debugPrint('🛡️ [PurchaseGuard] lock ignored (duplicate token) -> $t');
      return t;
    }

    _lockCount.value = _locks.length;

    if (_lockCount.value == 1) {
      _ctrl.add(true);
    }

    debugPrint('🛡️ [PurchaseGuard] lock -> ${_lockCount.value} token="$t"');
    return t;
  }

  /// 🔓 Sai do modo protegido
  /// Se você passar o mesmo token retornado pelo lock(), garante que não vai “destrancar errado”.
  void unlock({String? reason}) {
    final t = (reason ?? '').trim();

    if (t.isEmpty) {
      // Se não informar token, faz um unlock conservador: remove 1 qualquer (o mais antigo seria melhor,
      // mas Set não garante ordem). Melhor que estourar abaixo de 0.
      if (_locks.isNotEmpty) {
        final any = _locks.first;
        _locks.remove(any);
        debugPrint('🛡️ [PurchaseGuard] unlock (no token) removed="$any"');
      } else {
        debugPrint('🛡️ [PurchaseGuard] unlock ignored (no locks)');
      }
    } else {
      final removed = _locks.remove(t);
      if (!removed) {
        debugPrint('🛡️ [PurchaseGuard] unlock ignored (token not found) -> "$t"');
      }
    }

    _lockCount.value = _locks.length;

    if (_lockCount.value == 0) {
      _ctrl.add(false);
    }

    debugPrint('🛡️ [PurchaseGuard] state -> ${_lockCount.value} active=$activeLocks');
  }

  /// 🔄 Resgate: remove tudo
  void unlockAll({String? reason}) {
    _locks.clear();
    _lockCount.value = 0;
    _ctrl.add(false);

    debugPrint('🛡️ [PurchaseGuard] unlockAll -> 0 ${reason ?? ''}');
  }

  /// 🔄 Compat (mesma semântica antiga)
  void reset({String? reason}) => unlockAll(reason: reason);

  void dispose() {
    _ctrl.close();
    _lockCount.dispose();
  }
}
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const _key = 'device_id';
  static const _uuid = Uuid();

  // ✅ Cache em memória (evita múltiplos loads concorrentes)
  static String? _cachedId;
  static Future<String>? _inFlight;

  /// ID único por instalação do app (persistente).
  /// Estável enquanto os dados do app não forem apagados.
  static Future<String> getDeviceId() async {
    // Se já temos em memória, retorna direto
    final cached = _cachedId;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // Se já está sendo resolvido, reutiliza Future
    if (_inFlight != null) {
      return _inFlight!;
    }

    _inFlight = _resolveDeviceId();
    final id = await _inFlight!;

    _cachedId = id;
    _inFlight = null;

    return id;
  }

  static Future<String> _resolveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }

    final id = _uuid.v4();
    await prefs.setString(_key, id);
    return id;
  }

  /// (Opcional) útil só pra debug/teste
  static Future<void> resetDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);

    _cachedId = null;
    _inFlight = null;
  }
}
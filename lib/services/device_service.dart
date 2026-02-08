import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const _key = 'device_id';
  static const _uuid = Uuid();

  /// ID único por instalação do app (persistente).
  /// Evita duplicidade em emuladores e é estável em produção.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;

    final id = _uuid.v4();
    await prefs.setString(_key, id);
    return id;
  }

  /// (Opcional) útil só pra debug/teste
  static Future<void> resetDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

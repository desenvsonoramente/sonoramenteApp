import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static const _key = 'device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) return saved;

    final info = DeviceInfoPlugin();
    String id;

    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      id = android.id;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      id = ios.identifierForVendor ?? DateTime.now().toIso8601String();
    } else {
      id = DateTime.now().toIso8601String();
    }

    await prefs.setString(_key, id);
    return id;
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_settings.dart';

class SettingsRepository {
  SettingsRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'agent_base_url';
  static const _tokenKey = 'agent_device_token';
  final FlutterSecureStorage _secureStorage;

  Future<AgentSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final baseUrl = preferences.getString(_baseUrlKey) ?? '';
    final token = await _secureStorage.read(key: _tokenKey) ?? '';
    return AgentSettings(baseUrl: baseUrl, token: token);
  }

  Future<void> save(AgentSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, _normalizeUrl(settings.baseUrl));
    await _secureStorage.write(key: _tokenKey, value: settings.token.trim());
  }

  static String _normalizeUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

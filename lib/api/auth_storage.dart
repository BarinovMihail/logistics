import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Хранит учётные данные пользователя 1С (Basic Auth) между запусками
/// и собирает из них заголовок Authorization.
class AuthStorage {
  static const String _loginKey = 'auth_login';
  static const String _passwordKey = 'auth_password';

  static Future<bool> hasCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_loginKey) ?? '').isNotEmpty;
  }

  static Future<void> save(String login, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loginKey, login);
    await prefs.setString(_passwordKey, password);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginKey);
    await prefs.remove(_passwordKey);
  }

  /// Заголовок «Authorization: Basic …» для запросов к API.
  /// null — если сохранённых учётных данных нет (нужно идти на экран входа).
  static Future<String?> authHeader() async {
    final prefs = await SharedPreferences.getInstance();
    final login = prefs.getString(_loginKey);
    final password = prefs.getString(_passwordKey);
    if (login == null || login.isEmpty) return null;
    return 'Basic ${base64Encode(utf8.encode('$login:$password'))}';
  }
}

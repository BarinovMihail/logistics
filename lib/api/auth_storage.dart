import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Хранит учётные данные пользователя 1С (Basic Auth) между запусками
/// и собирает из них заголовок Authorization.
///
/// Вход в приложение всегда через экран авторизации; сохранённые учётные
/// данные используются только для предзаполнения полей, если пользователь
/// отметил «Запомнить учётную запись».
class AuthStorage {
  static const String _loginKey = 'auth_login';
  static const String _passwordKey = 'auth_password';
  static const String _rememberKey = 'auth_remember';

  /// Сохранённые учётные данные (или null), для предзаполнения экрана входа.
  static Future<({String login, String password})?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final login = prefs.getString(_loginKey);
    final password = prefs.getString(_passwordKey);
    if (login == null || login.isEmpty || password == null) return null;
    return (login: login, password: password);
  }

  /// Сохраняет учётные данные. [remember] — был ли отмечен чекбокс
  /// «Запомнить учётную запись»: если нет, данные будут стёрты при
  /// следующем запуске приложения (в рамках сеанса они работают).
  static Future<void> save(String login, String password,
      {bool remember = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loginKey, login);
    await prefs.setString(_passwordKey, password);
    await prefs.setBool(_rememberKey, remember);
  }

  /// Был ли прошлый вход с «Запомнить учётную запись».
  static Future<bool> wasRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? false;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_rememberKey);
  }

  /// Заголовок «Authorization: Basic …» для запросов к API.
  /// null — если учётных данных нет (пользователь ещё не входил).
  static Future<String?> authHeader() async {
    final creds = await read();
    if (creds == null) return null;
    return 'Basic ${base64Encode(utf8.encode('${creds.login}:${creds.password}'))}';
  }
}

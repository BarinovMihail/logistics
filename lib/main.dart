import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() {
  runApp(const LogisticsApp());
}

/// Приложение «Внутризаводская перевозка» — мобильный клиент рабочих-перевозчиков.
///
/// Данные берёт из HTTP-сервиса опубликованной базы 1С:ERP (только чтение,
/// GET). Тёмная/светлая тема — по системной, Material 3.
///
/// Вход в приложение всегда начинается с экрана авторизации: если рабочие
/// пользуются устройством по очереди, каждый входит под своей учётной записью
/// 1С. Отмеченная «Запомнить учётную запись» подставит сохранённый логин
/// и пароль в поля при следующем запуске.
class LogisticsApp extends StatelessWidget {
  const LogisticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1565C0);
    return MaterialApp(
      title: 'Внутризаводская перевозка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const LoginScreen(),
    );
  }
}

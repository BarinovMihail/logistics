import 'package:flutter/material.dart';

import 'api/auth_storage.dart';
import 'screens/login_screen.dart';
import 'screens/requests_list_screen.dart';

void main() {
  runApp(const LogisticsApp());
}

/// Приложение «Перевозки завода» — мобильный клиент рабочих-перевозчиков.
///
/// Данные берёт из HTTP-сервиса опубликованной базы 1С:ERP (только чтение,
/// GET). Тёмная/светлая тема — по системной, Material 3.
class LogisticsApp extends StatelessWidget {
  const LogisticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1565C0);
    return MaterialApp(
      title: 'Перевозки завода',
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
      home: const AuthGate(),
    );
  }
}

/// Выбирает стартовый экран: если учётные данные уже сохранены — сразу
/// список заявок, иначе — экран входа.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _hasCredentials = AuthStorage.hasCredentials();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCredentials,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true
            ? const RequestsListScreen()
            : const LoginScreen();
      },
    );
  }
}

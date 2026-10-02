import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exceptions.dart';
import '../api/api_service.dart';
import '../api/auth_storage.dart';
import '../update/update_controller.dart';
import 'requests_list_screen.dart';

/// Экран входа: логин и пароль пользователя 1С (Basic Auth).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  /// Предзаполнение сохранённой учёткой. Если прошлый вход был без
  /// «Запомнить» — стираем учётные данные (они были нужны только для
  /// закончившегося сеанса).
  ///
  /// Разовый автологин после обновления: перед установкой обновления
  /// контроллер запомнил ожидаемый versionCode; если сейчас установлена
  /// именно эта версия (обновление удалось) и учётка запомнена — входим
  /// сразу в список заявок, минуя ручной ввод.
  Future<void> _loadSavedCredentials() async {
    final saved = await AuthStorage.read();
    final remembered = await AuthStorage.wasRemembered();
    final autoLogin = await _updateJustInstalled();
    if (!mounted) return;
    if (saved != null && remembered) {
      _loginController.text = saved.login;
      _passwordController.text = saved.password;
      setState(() => _remember = true);
      if (autoLogin) {
        await _submit();
        return;
      }
    } else {
      await AuthStorage.clear();
      setState(() => _remember = false);
    }
  }

  /// Совпал ли установленный versionCode с тем, что ожидался при обновлении.
  /// Флаг одноразовый: проверяется и стирается при любом запуске.
  Future<bool> _updateJustInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getInt(UpdateController.pendingVersionKey);
    if (pending == null) return false;
    await prefs.remove(UpdateController.pendingVersionKey);
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    return current == pending;
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    // Сохраняем учётные данные и сразу проверяем их живым запросом к 1С;
    // если проверка не прошла — затираем, чтобы не остался невалидный вход.
    await AuthStorage.save(
      _loginController.text.trim(),
      _passwordController.text,
      remember: _remember,
    );
    try {
      await _api.getRequests();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RequestsListScreen()),
      );
    } on UnauthorizedException {
      await AuthStorage.clear();
      if (!mounted) return;
      setState(() {
        _error = 'Неверный логин или пароль.';
        _loading = false;
      });
    } on ApiException catch (e) {
      await AuthStorage.clear();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.local_shipping,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Внутризаводская перевозка',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Вход для рабочих-перевозчиков (учётная запись 1С)',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _loginController,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Введите логин'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_loading,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_loading) _submit();
                    },
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value == null || value.isEmpty)
                            ? 'Введите пароль'
                            : null,
                  ),
                  CheckboxListTile(
                    value: _remember,
                    onChanged: _loading
                        ? null
                        : (value) =>
                            setState(() => _remember = value ?? false),
                    title: const Text('Запомнить учётную запись'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Text(
                              'ВОЙТИ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

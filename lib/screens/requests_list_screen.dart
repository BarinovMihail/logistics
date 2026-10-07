import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exceptions.dart';
import '../api/api_service.dart';
import '../api/auth_storage.dart';
import '../models/request_model.dart';
import '../update/update_controller.dart';
import '../widgets/error_view.dart';
import '../widgets/request_card.dart';
import 'login_screen.dart';
import 'request_detail_screen.dart';

/// Экран 1 — список активных заявок на внутризаводскую перевозку.
class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen>
    with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final UpdateController _updates = UpdateController();

  List<TransportRequest>? _requests;
  String? _currentLogin;
  bool _loading = false;
  bool _updateDialogShown = false;
  bool _updateDialogOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.addListener(_onUpdateChanged);
    _loadCurrentLogin();
    _load();
  }

  /// Логин вошедшего пользователя — для пометки «текущая задача»
  /// (заявка «В работе», исполнитель которой совпадает с логином).
  Future<void> _loadCurrentLogin() async {
    final creds = await AuthStorage.read();
    if (!mounted) return;
    setState(() => _currentLogin = creds?.login);
  }

  /// Заявка в работе у текущего пользователя.
  bool _isCurrentTask(TransportRequest request) =>
      _currentLogin != null &&
      request.executor == _currentLogin &&
      request.isInWork;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updates.removeListener(_onUpdateChanged);
    _updates.dispose();
    super.dispose();
  }

  /// Планшет проснулся после блокировки (или пользователь вернулся из
  /// системного установщика). Если в фоне скачивание упало в ошибку или
  /// диалог «Запущен установщик» остался висеть (установку отменили) —
  /// тихо закрываем диалог и перепроверяем: если обновление ещё доступно,
  /// диалог откроется заново в нормальном виде.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final current = _updates.state;
    final stale = current is UpdateError || current is UpdateInstalling;
    if (!stale) return;
    if (_updateDialogOpen) {
      Navigator.of(context).pop();
      _updateDialogOpen = false;
    }
    _updates.skip();
    unawaited(_updates.checkForUpdate());
  }

  /// Показываем диалог, как только появилась доступная версия.
  void _onUpdateChanged() {
    if (_updates.state is UpdateAvailable && !_updateDialogShown && mounted) {
      _updateDialogShown = true;
      _showUpdateDialog();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await _api.getRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
      // Проверка обновления из публичной папки Яндекс Диска — тихая,
      // результат (если есть) покажется диалогом.
      unawaited(_updates.checkForUpdate());
    } on UnauthorizedException {
      await _logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// 401 — учётные данные недействительны: чистим хранилище
  /// и возвращаемся на экран входа.
  Future<void> _logout() async {
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openDetails(TransportRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(requestNumber: request.number),
      ),
    );
    // Вернулись с карточки — обновляем список: статус, исполнитель или
    // состав заявок могли измениться (взял в работу, выполнил, фото).
    if (mounted) await _load();
  }

  /// Диалог автообновления: версия + примечания → скачивание с прогрессом →
  /// запуск системного установщика. Для обязательных обновлений нет «Позже».
  Future<void> _showUpdateDialog() async {
    _updateDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ListenableBuilder(
        listenable: _updates,
        builder: (context, _) {
          final state = _updates.state;

          final Widget content;
          final List<Widget> actions;

          switch (state) {
            case UpdateAvailable():
              content = SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Версия ${state.manifest.versionName}'),
                    if (state.manifest.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.manifest.releaseNotes,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              );
              actions = [
                if (!state.manifest.required)
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _updates.skip();
                    },
                    child: const Text('Позже'),
                  ),
                FilledButton(
                  onPressed: _updates.downloadAndInstall,
                  child: const Text('Обновить'),
                ),
              ];
            case UpdateDownloading():
              final progress = state.progress;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text(progress == null
                      ? 'Скачивание обновления…'
                      : 'Скачивание… ${(progress * 100).round()}%'),
                ],
              );
              actions = const [];
            case UpdateNeedsPermission():
              content = SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Система запрещает приложению устанавливать обновления. '
                      'В открывшихся настройках включите «Разрешить из этого '
                      'источника», вернитесь и нажмите «Повторить установку».',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Версия ${state.manifest.versionName} · '
                      '${state.manifest.releaseNotes}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
              actions = [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _updates.skip();
                  },
                  child: const Text('Позже'),
                ),
                TextButton(
                  onPressed: () => _updates.openInstallPermissionSettings(),
                  child: const Text('Открыть настройки'),
                ),
                FilledButton(
                  onPressed: _updates.retryInstall,
                  child: const Text('Повторить установку'),
                ),
              ];
            case UpdateInstalling():
              content = const Text(
                'Запущен установщик — подтвердите установку на экране '
                'устройства. Если установщик не открылся (или вы отменили '
                'установку), нажмите «Закрыть» и запустите обновление '
                'повторно.',
              );
              actions = [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _updates.skip();
                  },
                  child: const Text('Закрыть'),
                ),
              ];
            case UpdateError():
              content = Text(state.message);
              actions = [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _updates.skip();
                  },
                  child: const Text('Позже'),
                ),
                FilledButton(
                  onPressed: _updates.retry,
                  child: const Text('Повторить'),
                ),
              ];
            default:
              content = const SizedBox.shrink();
              actions = [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Закрыть'),
                ),
              ];
          }

          return AlertDialog(
            title: Text(
              switch (state) {
                UpdateInstalling() => 'Обновление',
                UpdateError() => 'Ошибка обновления',
                _ => 'Доступно обновление',
              },
            ),
            content: content,
            actions: actions,
          );
        },
        ),
      );
    } finally {
      _updateDialogOpen = false;
      _updateDialogShown = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заявки на перевозку'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _requests == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final requests = _requests ?? const <TransportRequest>[];
    if (requests.isEmpty) {
      return Center(
        child: Text(
          'Нет активных заявок',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    // Заявки текущего пользователя в работе — первыми (пометка «текущая
    // задача»), внутри групп порядок сервера (по дате) сохраняется.
    final currentTasks = <TransportRequest>[];
    final others = <TransportRequest>[];
    for (final request in requests) {
      (_isCurrentTask(request) ? currentTasks : others).add(request);
    }
    final sorted = [...currentTasks, ...others];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // Нижний отступ: последняя карточка (включая строку с датой)
        // не должна обрезаться краем экрана.
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final request = sorted[index];
          return RequestCard(
            request: request,
            onTap: () => _openDetails(request),
            isCurrentTask: _isCurrentTask(request),
          );
        },
      ),
    );
  }
}

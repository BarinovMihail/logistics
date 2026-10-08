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
    // Проверка обновлений зависит только от интернета (Яндекс Диск),
    // поэтому идёт сразу при запуске — даже если 1С недоступен и список
    // не загрузился: иначе устройство без доступа к базе никогда не
    // получило бы обновление.
    unawaited(_updates.checkForUpdate());
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

  /// Выбор транспортного средства для заявки «Готова к выполнению»:
  /// снизу выезжает список ТС нужного вида, по тапу — POST /transport.
  Future<void> _chooseVehicle(TransportRequest request) async {
    if (request.vehicleKind.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В заявке не указан вид транспорта — '
              'заполните его в 1С'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final vehicle = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.3,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (context, scrollController) => _VehiclePickerSheet(
          request: request,
          vehiclesFuture: _api.getVehicles(request.vehicleKindJoined),
          scrollController: scrollController,
          onPicked: (vehicle) => Navigator.of(sheetContext).pop(vehicle),
        ),
      ),
    );
    if (vehicle == null || !mounted) return;
    await _assignVehicle(request, vehicle);
  }

  /// Назначение выбранного ТС заявке (POST /transport) и обновление списка.
  Future<void> _assignVehicle(TransportRequest request, String vehicle) async {
    try {
      await _api.assignTransport(request.number, vehicle);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Назначен транспорт: $vehicle'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _load();
    } on UnauthorizedException {
      await _logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 4)),
      );
    }
  }

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
      // Проверка обновлений при каждом обновлении списка (pull-to-refresh,
      // возврат с карточки) — тихая; повтор не запустится, пока идёт
      // проверка/скачивание (защита внутри UpdateController).
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
        builder: (_) => RequestDetailScreen(
          requestNumber: request.number,
          // Карточка заявки пока не отдаёт «Транспорт» — передаём из списка.
          initialTransport: request.transport.isEmpty ? null : request.transport,
        ),
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
            onTransportTap: request.isReadyForExecution
                ? () => _chooseVehicle(request)
                : null,
          );
        },
      ),
    );
  }

}


  /// Панель выбора транспортного средства: заголовок + список ТС нужного вида.
class _VehiclePickerSheet extends StatelessWidget {
  const _VehiclePickerSheet({
    required this.request,
    required this.vehiclesFuture,
    required this.scrollController,
    required this.onPicked,
  });

  final TransportRequest request;
  final Future<List<String>> vehiclesFuture;
  final ScrollController scrollController;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Выберите транспорт',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Заявка № ${request.number} · вид: ${request.vehicleKind}'
                '${request.transport.isEmpty ? '' : ' · сейчас: ${request.transport}'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: vehiclesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Не удалось загрузить список транспорта',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                );
              }
              final vehicles = snapshot.data ?? const <String>[];
              if (vehicles.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Нет транспорта вида «${request.vehicleKind}»',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: scrollController,
                itemCount: vehicles.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.local_shipping),
                  title: Text(vehicles[index],
                      style: const TextStyle(fontSize: 18)),
                  onTap: () => onPicked(vehicles[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


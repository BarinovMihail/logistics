import 'package:flutter/material.dart';

import '../api/api_exceptions.dart';
import '../api/api_service.dart';
import '../api/auth_storage.dart';
import '../models/request_model.dart';
import '../widgets/error_view.dart';
import '../widgets/status_badge.dart';
import 'login_screen.dart';

/// Экран 2 — карточка заявки (загружается по номеру с сервера).
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.requestNumber});

  final String requestNumber;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  final ApiService _api = ApiService();

  TransportRequest? _request;
  bool _loading = false;
  bool _taking = false;
  bool _completing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final request = await _api.getRequest(widget.requestNumber);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
      });
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

  /// «Выполнено»: POST /requests/complete. Сервер переводит заявку
  /// в «Ожидает подтверждения мастера» (или сразу «Завершена») и создаёт
  /// задачу мастеру; отказ показываем текстом из {"error": …}.
  Future<void> _completeRequest() async {
    final request = _request;
    if (request == null || _completing) return;
    setState(() => _completing = true);
    try {
      await _api.completeRequest(request.number);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заявка выполнена'),
          duration: Duration(seconds: 2),
        ),
      );
      await _load();
    } on UnauthorizedException {
      await _logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), duration: const Duration(seconds: 4)),
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  /// «Взять в работу»: POST /requests/take, после успеха перезагружаем
  /// карточку (статус, исполнитель, дата взятия). Отказ сервера (400)
  /// показываем текстом из {"error": …}.
  Future<void> _takeRequest() async {
    final request = _request;
    if (request == null || _taking) return;
    setState(() => _taking = true);
    try {
      await _api.takeRequest(request.number);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заявка взята в работу'),
          duration: Duration(seconds: 2),
        ),
      );
      await _load();
    } on UnauthorizedException {
      await _logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), duration: const Duration(seconds: 4)),
      );
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Заявка № ${widget.requestNumber}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (request != null) ...[
              const SizedBox(width: 12),
              Flexible(child: StatusBadge(status: request.status)),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (request != null) _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _request == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    final request = _request;
    if (request == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _SectionCard(
          title: 'Груз',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(label: 'Изделие', value: request.item, emphasized: true),
              _Field(label: 'ККМ', value: request.kkm),
              _Field(
                label: 'Подразделение',
                value: request.subdivision.isEmpty
                    ? '—'
                    : request.subdivision,
              ),
              _Field(label: 'Количество', value: '${request.quantity} шт'),
            ],
          ),
        ),
        _SectionCard(
          title: 'Маршрут',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoutePoint(place: request.fromDisplay),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.south, color: Colors.grey),
              ),
              _RoutePoint(place: request.toDisplay),
            ],
          ),
        ),
        if (request.specialConditions != null)
          _SectionCard(
            title: 'Условия',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Text(
                request.specialConditions!,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
          ),
        _SectionCard(
          title: 'Требования',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Requirement(
                fulfilled: request.requiresPhoto,
                requiredText: '📷 Требуется фото',
                notRequiredText: 'Фото не требуется',
              ),
              const SizedBox(height: 12),
              _Requirement(
                fulfilled: request.requiresMaster,
                requiredText: '👤 Требуется мастер',
                notRequiredText: 'Мастер не требуется',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Исполнитель: ${request.executor ?? '—'}',
          style: _footerStyle(context),
        ),
        Text(
          'Взята в работу: ${formatDate(request.takenAt)}',
          style: _footerStyle(context),
        ),
        Text(
          'Выполнена: ${formatDate(request.completedAt)}',
          style: _footerStyle(context),
        ),
      ],
    );
  }

  TextStyle _footerStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Widget _buildButtons() {
    final request = _request;
    if (request == null) return const SizedBox.shrink();

    // Доступность по статусу (сервер дополнительно проверяет сам):
    //  • «Взять в работу» — пока заявка не в работе и не ждёт мастера;
    //  • «Выполнено» — только когда заявка в работе.
    final canTake = !request.isInWork && !request.isWaitingMaster;
    final canComplete = request.isInWork;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTakeButton(enabled: canTake),
          const SizedBox(height: 12),
          _buildCompleteButton(enabled: canComplete),
        ],
      ),
    );
  }

  /// Кнопка «Взять в работу» — POST /requests/take.
  Widget _buildTakeButton({required bool enabled}) {
    return ElevatedButton(
      onPressed: !_taking && enabled ? _takeRequest : null,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      child: _taking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : const Text('ВЗЯТЬ В РАБОТУ'),
    );
  }

  /// Кнопка «Выполнено» — POST /requests/complete.
  Widget _buildCompleteButton({required bool enabled}) {
    return ElevatedButton(
      onPressed: !_completing && enabled ? _completeRequest : null,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      child: _completing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : const Text('ВЫПОЛНЕНО'),
    );
  }
}

/// Секция карточки с заголовком («Груз», «Маршрут», …).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Пара «подпись — значение» внутри секции.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: emphasized
                ? const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)
                : const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Пункт маршрута («Откуда» / «Куда»).
class _RoutePoint extends StatelessWidget {
  const _RoutePoint({required this.place});

  final String place;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            place,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Требование (фото/мастер): зелёная галочка или «не требуется».
class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.fulfilled,
    required this.requiredText,
    required this.notRequiredText,
  });

  final bool fulfilled;
  final String requiredText;
  final String notRequiredText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          fulfilled ? Icons.check_circle : Icons.do_not_disturb_on,
          color: fulfilled ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            fulfilled ? requiredText : notRequiredText,
            style: TextStyle(
              fontSize: 17,
              fontWeight: fulfilled ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

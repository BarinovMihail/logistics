import 'package:flutter/material.dart';

import '../api/api_exceptions.dart';
import '../api/api_service.dart';
import '../api/auth_storage.dart';
import '../models/request_model.dart';
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

class _RequestsListScreenState extends State<RequestsListScreen> {
  final ApiService _api = ApiService();

  List<TransportRequest>? _requests;
  bool _loading = false;
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
      final requests = await _api.getRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _openDetails(TransportRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(requestNumber: request.number),
      ),
    );
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          return RequestCard(
            request: request,
            onTap: () => _openDetails(request),
          );
        },
      ),
    );
  }
}

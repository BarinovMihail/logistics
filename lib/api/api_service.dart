import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/request_model.dart';
import 'api_exceptions.dart';
import 'auth_storage.dart';

/// Клиент HTTP-сервиса опубликованной базы 1С:ERP.
class ApiService {
  /// Адреса HTTP-сервиса 1С — единственное место в проекте, где задан сервер.
  ///
  /// [apiBaseUrl] — прямой адрес компьютера с опубликованной базой в заводской
  /// сети (как localUrl в проекте TSD). Работает, когда телефон в сети,
  /// имеющей маршрут до 192.168.x.x (заводской Wi-Fi, если ИТ его откроет).
  ///
  /// [apiFallbackUrl] — резерв через USB-кабель: localhost:8080 на телефоне
  /// пробрасывается на этот компьютер командой (слетает при переподключении
  /// кабеля — повторить; порт 80 на самом телефоне adbd занять не может —
  /// привилегированный):
  ///
  ///   adb reverse tcp:8080 tcp:80
  ///
  /// Путь к базе — в нижнем регистре: Apache публикует её как /erp_local,
  /// и запрос с «ERP_Local» получает 301-редирект, после которого POST
  /// превращается в GET.
  ///
  /// Клиент перебирает адреса по порядку при сетевых ошибках (см. [_send]
  /// и [_preferredHost]) — как failover в DioClient проекта TSD.
  static const String apiBaseUrl = 'http://192.168.1.51/erp_local/hs/log';
  static const String apiFallbackUrl = 'http://localhost:8080/erp_local/hs/log';

  static const List<String> _hosts = [apiBaseUrl, apiFallbackUrl];

  /// Таймаут всех сетевых запросов (последняя попытка).
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Таймаут не последней попытки — недоступный хост не должен надолго
  /// задерживать переключение на резервный.
  static const Duration _failoverTimeout = Duration(seconds: 5);

  /// Индекс хоста, который ответил последним; с него начинаем следующий запрос.
  static int _preferredHost = 0;

  /// GET /requests — список всех активных заявок
  /// (закрытые статусы уже отфильтрованы на сервере).
  Future<List<TransportRequest>> getRequests() async {
    final data = await _getJson('/requests');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(TransportRequest.fromJson)
        .toList();
  }

  /// GET /requests/{Номер} — карточка заявки.
  Future<TransportRequest> getRequest(String number) async {
    final data = await _getJson('/requests/${Uri.encodeComponent(number)}');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Некорректный ответ сервера.');
    }
    return TransportRequest.fromJson(data);
  }

  /// POST /requests/take — взять заявку в работу.
  /// Сервер проверяет статус и исполнителя: при отказе отвечает
  /// 400 с текстом ошибки в {"error": "…"} — он попадёт в ApiException.
  Future<void> takeRequest(String num) async {
    await _postJson('/requests/take', {'num': num});
  }

  /// POST /requests/complete — выполнить заявку.
  /// Сервер проверяет, что заявка «В работе» у текущего исполнителя, затем
  /// переводит её в «Ожидает подтверждения мастера» (или сразу «Завершена»,
  /// если мастер не требуется) и создаёт задачу мастеру на подтверждение.
  /// Отказ — 400 с текстом в {"error": "…"}.
  ///
  /// [photoBase64] — фото выполнения; текущий эндпоинт его не принимает,
  /// параметр оставлен под будущий контракт ({"num", "photo"}).
  Future<void> completeRequest(String num, {String? photoBase64}) async {
    final body = <String, dynamic>{'num': num};
    if (photoBase64 != null) {
      body['photo'] = photoBase64;
    }
    await _postJson('/requests/complete', body);
  }

  // --- Сетевой уровень ---

  Future<dynamic> _getJson(String path) async {
    final response =
        await _send((uri, headers) => http.get(uri, headers: headers), path);
    return _decode(response);
  }

  /// Помощник для будущих POST-запросов (TODO в takeRequest/completeRequest).
  // ignore: unused_element
  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    final response = await _send(
      (uri, headers) => http.post(
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _decode(response);
  }

  Future<http.Response> _send(
    Future<http.Response> Function(Uri uri, Map<String, String> headers)
        action,
    String path,
  ) async {
    final authHeader = await AuthStorage.authHeader();
    if (authHeader == null) {
      throw const UnauthorizedException();
    }

    // Перебираем адреса, начиная с последнего удачного (failover как в TSD).
    // Переключаемся только при сетевых ошибках; HTTP-ответы сервера
    // (401/404/400…) — реальный ответ 1С, не повод пробовать другой адрес.
    for (var attempt = 0; attempt < _hosts.length; attempt++) {
      final index = (_preferredHost + attempt) % _hosts.length;
      final isLast = attempt == _hosts.length - 1;
      try {
        final response = await action(
          Uri.parse('${_hosts[index]}$path'),
          {'Authorization': authHeader, 'Accept': 'application/json'},
        ).timeout(isLast ? requestTimeout : _failoverTimeout);
        _preferredHost = index;
        return response;
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      } on http.ClientException {
        continue;
      }
    }
    throw const ApiException(
      'Нет связи с сервером. Проверьте подключение к сети (Wi-Fi или '
      'USB-кабель с командой adb reverse tcp:8080 tcp:80).',
    );
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      body = null;
    }

    switch (response.statusCode) {
      case 200:
        if (body is Map<String, dynamic> && body.containsKey('data')) {
          return body['data'];
        }
        if (body != null) return body;
        throw const ApiException('Некорректный ответ сервера.');
      case 401:
        throw const UnauthorizedException('Неверный логин или пароль.');
      default:
        // Сервер сообщает об ошибках так: {"error": "Заявка … не найдена."}
        final error = body is Map ? body['error'] : null;
        throw ApiException(
          error is String && error.isNotEmpty
              ? error
              : 'Ошибка сервера (код ${response.statusCode}).',
          statusCode: response.statusCode,
        );
    }
  }
}

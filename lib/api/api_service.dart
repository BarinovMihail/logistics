import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/request_model.dart';
import 'api_exceptions.dart';
import 'auth_storage.dart';

/// Клиент HTTP-сервиса опубликованной базы 1С:ERP.
class ApiService {
  /// Базовый URL HTTP-сервиса — единственное место в проекте,
  /// где задан адрес сервера.
  ///
  /// 192.168.1.51 — адрес компьютера с опубликованной базой 1С в заводской
  /// сети (узнать: `ipconfig`). Телефон должен быть в той же сети (заводской
  /// Wi-Fi); USB-кабель и `adb reverse` при таком адресе не нужны.
  ///
  /// Путь к базе — в нижнем регистре: Apache публикует её как /erp_local,
  /// и запрос с «ERP_Local» получает 301-редирект, после которого POST
  /// превращается в GET.
  ///
  /// Внимание: адрес может измениться при обновлении аренды DHCP —
  /// если приложение перестанет подключаться, сверьте IP через `ipconfig`
  /// или попросите ИТ закрепить адрес за этим компьютером.
  static const String apiBaseUrl = 'http://192.168.1.51/erp_local/hs/log';

  /// Таймаут всех сетевых запросов.
  static const Duration requestTimeout = Duration(seconds: 15);

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

  /// POST /requests/complete — выполнить заявку (photo — фото в base64).
  ///
  /// TODO: POST-эндпоинт на сервере ещё не реализован, из UI не вызывается.
  /// Когда появится — раскомментировать вызов _postJson ниже и включить
  /// кнопку «ВЫПОЛНЕНО» на экране карточки заявки.
  Future<void> completeRequest(String num, String photoBase64) async {
    // await _postJson('/requests/complete', {'num': num, 'photo': photoBase64});
    throw const ApiException('Операция пока недоступна');
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

    try {
      return await action(
        Uri.parse('$apiBaseUrl$path'),
        {'Authorization': authHeader, 'Accept': 'application/json'},
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Сервер не ответил за 15 секунд. Проверьте связь с сетью завода.',
      );
    } on SocketException {
      throw const ApiException(
        'Нет связи с сервером. Проверьте подключение к сети.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Не удалось подключиться к серверу. Попробуйте ещё раз.',
      );
    }
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

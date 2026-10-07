import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/request_model.dart';
import 'api_exceptions.dart';
import 'auth_storage.dart';

/// Клиент HTTP-сервиса опубликованной базы 1С:ERP.
class ApiService {
  /// Адреса HTTP-сервиса 1С — единственное место в проекте, где задан сервер.
  ///
  /// Приоритет подключения (как в проекте «Регистрация нарушений»):
  /// **мобильная сеть → Wi-Fi → USB**. Клиент перебирает адреса по порядку
  /// при сетевых ошибках и запоминает последний удачный (см. [_send] и
  /// [_preferredHost]); HTTP-ответы сервера (401/404/400…) переключение
  /// не вызывают.
  ///
  /// [apiMobileUrl] — публичный адрес этой же базы (ERP_Local на этом ПК)
  /// из интернета: порт 8182 на роутере завода проброшен на 192.168.1.51:80.
  /// Работает только из мобильной сети: из заводской сети внешний адрес
  /// недоступен (нет hairpin NAT) — клиент молча перейдёт на Wi-Fi/USB.
  static const String apiMobileUrl =
      'http://81.211.118.58:8182/erp_local/hs/log';

  /// [apiBaseUrl] — прямой адрес компьютера с базой в заводской сети
  /// (Wi-Fi/LAN, когда есть маршрут до 192.168.x.x).
  static const String apiBaseUrl = 'http://192.168.1.51/erp_local/hs/log';

  /// [apiFallbackUrl] — резерв через USB-кабель: localhost:8080 на телефоне
  /// пробрасывается на этот компьютер командой `adb reverse tcp:8080 tcp:80`
  /// (слетает при переподключении кабеля; порт 80 на телефоне adbd занять
  /// не может — привилегированный).
  static const String apiFallbackUrl = 'http://localhost:8080/erp_local/hs/log';

  /// Адреса в порядке приоритета: мобильная сеть (если задана) → Wi-Fi → USB.
  static List<String> get _hosts => [
        if (apiMobileUrl.isNotEmpty) apiMobileUrl,
        apiBaseUrl,
        apiFallbackUrl,
      ];

  /// Таймаут всех сетевых запросов (последняя попытка).
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Таймаут не последней попытки — недоступный хост не должен надолго
  /// задерживать переключение на резервный.
  static const Duration _failoverTimeout = Duration(seconds: 5);

  /// Индекс хоста, который ответил последним; с него начинаем следующий запрос.
  static int _preferredHost = 0;

  /// GET /requests — список всех активных заявок.
  ///
  /// По контракту закрытые статусы («Завершена», «Перевозка не требуется»,
  /// «Отменена») отфильтровывает сервер; на случай, когда он отдаёт всё,
  /// дублируем фильтр на клиенте.
  Future<List<TransportRequest>> getRequests() async {
    const closedStatuses = {'Завершена', 'Перевозка не требуется', 'Отменена'};
    final data = await _getJson('/requests');
    final rows = data is List ? data : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(TransportRequest.fromJson)
        .where((request) => !closedStatuses.contains(request.status))
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

  /// POST с сохранением метода и тела при редиректах.
  ///
  /// Встроенное авто-следование перенаправлениям превращает POST в GET
  /// (RFC 301/302/303), из-за чего загрузка фото падала с «Ошибка сервера
  /// (код 301)»: Apache канонизирует путь фото в /ERP_Local/…/photo/ через
  /// 301. Здесь редиректы отключены и обрабатываются вручную — повторным
  /// POST по Location (до 3 переходов), с тем же телом.
  Future<http.Response> _postPreservingMethod(
    Uri uri,
    Map<String, String> headers, {
    List<int>? bytes,
    String? jsonBody,
    int redirectsLeft = 3,
  }) async {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (jsonBody != null) {
      request.body = jsonBody;
    }
    final client = http.Client();
    http.Response response;
    try {
      final streamed = await client.send(request);
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      client.close();
      rethrow;
    }
    client.close();

    final location = response.headers['location'];
    final isRedirect = const {301, 302, 303, 307, 308}
        .contains(response.statusCode);
    if (isRedirect &&
        location != null &&
        location.isNotEmpty &&
        redirectsLeft > 0) {
      return _postPreservingMethod(
        uri.resolve(location),
        headers,
        bytes: bytes,
        jsonBody: jsonBody,
        redirectsLeft: redirectsLeft - 1,
      );
    }
    return response;
  }

  /// POST /requests/photo?num=… — загрузить фото выполнения заявки.
  /// Тело запроса — двоичные данные изображения (Content-Type image/jpeg),
  /// номер заявки — query-параметр num. Сервер сохраняет фото как
  /// присоединённый файл заявки и отвечает именем файла (JSON {"data": …}).
  Future<String> uploadPhoto(String num, Uint8List bytes,
      {String mimeType = 'image/jpeg'}) async {
    final response = await _send(
      (uri, headers) => _postPreservingMethod(
        uri.replace(queryParameters: {'num': num}),
        {...headers, 'Content-Type': mimeType},
        bytes: bytes,
      ),
      '/requests/photo',
    );
    final data = _decode(response);
    return data?.toString() ?? '';
  }

  /// GET /requests/checkphoto/{num} — есть ли уже фото у заявки.
  /// Возвращает {"data": {"num": "…", "hasPhoto": true|false}}.
  /// Ошибка сети/сервера пробрасывается вызывающему коду.
  Future<bool> requestHasPhoto(String requestNumber) async {
    final data = await _getJson(
      '/requests/checkphoto/${Uri.encodeComponent(requestNumber)}',
    );
    if (data is Map<String, dynamic>) {
      final value = data['hasPhoto'];
      if (value is bool) return value;
      if (value is int || value is double) return value != 0;
      final text = value?.toString().toLowerCase();
      return text == 'true' || text == 'да' || text == '1';
    }
    return false;
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
      (uri, headers) => _postPreservingMethod(
        uri,
        {...headers, 'Content-Type': 'application/json'},
        jsonBody: jsonEncode(body),
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

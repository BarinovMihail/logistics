// Проверка модели и сетевого слоя на живом сервере 1С (без запуска приложения):
//
//   dart run tool/check_api.dart testLog 7zyriqoL
//
// Скрипт повторяет то же, что делает ApiService (Basic Auth, redirect Apache,
// разбор русских ключей JSON), но подставляет учётные данные из аргументов
// вместо shared_preferences.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logistics/models/request_model.dart';

const String apiBaseUrl = 'http://localhost/ERP_Local/hs/log';
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Использование: dart run tool/check_api.dart <логин> <пароль>');
    return;
  }
  final headers = {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('${args[0]}:${args[1]}'))}',
    'Accept': 'application/json',
  };

  print('=== GET /requests ===');
  final listResponse = await http
      .get(Uri.parse('$apiBaseUrl/requests'), headers: headers)
      .timeout(const Duration(seconds: 15));
  print('HTTP ${listResponse.statusCode}, '
      'final url: ${listResponse.request?.url}');
  final listJson = jsonDecode(utf8.decode(listResponse.bodyBytes));
  final rows = (listJson['data'] as List).cast<Map<String, dynamic>>();
  final requests = rows.map(TransportRequest.fromJson).toList();
  print('Загружено заявок: ${requests.length}');
  for (final r in requests) {
    print('  №${r.number} [${r.status}] ${r.item} — ${r.quantity} шт, '
        '${r.fromDisplay} -> ${r.toDisplay}, '
        'подразделение=${r.subdivision.isEmpty ? '—' : r.subdivision}, '
        'фото=${r.requiresPhoto}, мастер=${r.requiresMaster}, '
        'дата=${formatDate(r.date)}');
  }

  print('\n=== GET /requests/${requests.first.number} ===');
  final detailResponse = await http
      .get(Uri.parse('$apiBaseUrl/requests/${requests.first.number}'),
          headers: headers)
      .timeout(const Duration(seconds: 15));
  print('HTTP ${detailResponse.statusCode}');
  final detailJson = jsonDecode(utf8.decode(detailResponse.bodyBytes));
  final detail = TransportRequest.fromJson(detailJson['data']);
  print('  ОсобыеУсловия: ${detail.specialConditions ?? '—'}');
  print('  Исполнитель: ${detail.executor ?? '—'}');
  print('  Взята в работу: ${formatDate(detail.takenAt)}');
  print('  Выполнена: ${formatDate(detail.completedAt)}');
}

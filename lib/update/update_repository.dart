import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_config.dart';
import 'version_manifest.dart';

/// Колбэк прогресса скачивания: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK из публичной папки
/// Яндекс Диска (портировано из проекта TSD).
///
/// Цепочка: приложение → REST API Яндекс Диска (публичные эндпоинты,
/// без токена): `GET /public/resources/download?public_key=...&path=...`
/// → временная прямая ссылка (href) → скачивание файла.
///
/// APK может лежать на Диске как `.apk`, так и `.zip`-архивом — формат
/// определяется по расширению apkPath; SHA-256 всегда проверяется по
/// итоговому APK.
class UpdateRepository {
  UpdateRepository({UpdateConfig? config, http.Client? client})
      : _config = config ?? kUpdateConfig,
        _client = client ?? http.Client();

  final UpdateConfig _config;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 60);

  /// GET манифеста версий из публичной папки Диска.
  /// Ошибки не бросает наружу: при любой проблеме возвращает null —
  /// проверка обновлений не должна мешать работе приложения.
  Future<VersionManifest?> checkForUpdate() async {
    try {
      final href = await _resolveDownloadHref(_config.manifestPath);
      final bytes = await _downloadBytes(href);
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) return null;
      return VersionManifest.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Скачать APK (или zip с APK), проверить SHA-256, вернуть файл.
  /// Бросает [UpdateException] с понятным сообщением при проблемах.
  Future<File> downloadApk(
    VersionManifest manifest, {
    DownloadProgress? onProgress,
  }) async {
    if (!manifest.isValid) {
      throw const UpdateException('Манифест обновления некорректен.');
    }

    final dir = await getTemporaryDirectory();
    final isZip = manifest.apkPath.toLowerCase().endsWith('.zip');
    final href = await _resolveDownloadHref(manifest.apkPath);

    final File downloaded;
    if (isZip) {
      downloaded = File(p.join(dir.path, 'update.zip'));
      await _downloadToFile(href, downloaded, onProgress);
    } else {
      downloaded = File(p.join(dir.path, 'update.apk'));
      await _downloadToFile(href, downloaded, onProgress);
    }

    final apkFile =
        isZip ? await _extractApk(downloaded, dir) : downloaded;

    final actual = await _sha256OfFile(apkFile);
    if (actual.toLowerCase() != manifest.sha256.toLowerCase()) {
      await _tryDelete(downloaded);
      await _tryDelete(apkFile);
      throw const UpdateException(
        'Файл обновления повреждён (не совпала контрольная сумма). '
        'Попробуйте ещё раз.',
      );
    }
    return apkFile;
  }

  /// Запрос временной прямой ссылки на файл [path] внутри публичной папки.
  /// Диск требует путь относительно корня публичной папки с ведущим «/».
  Future<String> _resolveDownloadHref(String path) async {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${_config.apiBase}/public/resources/download')
        .replace(
      queryParameters: {
        'public_key': _config.publicKey,
        'path': normalized,
      },
    );
    final response = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw UpdateException('Диск вернул код ${response.statusCode}.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final href = data is Map ? data['href'] : null;
    if (href is! String || href.isEmpty) {
      throw const UpdateException('Некорректный ответ Яндекс Диска.');
    }
    return href;
  }

  Future<List<int>> _downloadBytes(String href) async {
    final response = await _client.get(Uri.parse(href)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw UpdateException('Сервер вернул код ${response.statusCode}.');
    }
    return response.bodyBytes;
  }

  /// Скачивание в файл с прогрессом (через streamed-запрос http).
  Future<void> _downloadToFile(
    String href,
    File target,
    DownloadProgress? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(href));
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode != 200) {
      throw UpdateException('Сервер вернул код ${response.statusCode}.');
    }
    final total = response.contentLength ?? 0;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Распаковка zip → извлечение единственного `.apk` в [dir].
  Future<File> _extractApk(File zipFile, Directory dir) async {
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    ArchiveFile? apk;
    for (final f in archive) {
      if (f.name.toLowerCase().endsWith('.apk')) {
        if (apk != null) {
          throw const UpdateException('В архиве более одного APK.');
        }
        apk = f;
      }
    }
    if (apk == null) {
      throw const UpdateException('В архиве нет APK.');
    }
    final apkFile = File(p.join(dir.path, 'update.apk'));
    await apkFile.writeAsBytes(apk.content as List<int>, flush: true);
    await _tryDelete(zipFile);
    return apkFile;
  }

  /// SHA-256 файла (потоково, чтобы не грузить весь APK в память).
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<void> _tryDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // файл мог уже удалиться — не критично
    }
  }
}

/// Ошибка обновления с понятным пользователю сообщением.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

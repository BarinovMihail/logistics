import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'apk_installer.dart';
import 'update_repository.dart';
import 'version_manifest.dart';

/// Состояние проверки обновлений (упрощённый вариант UpdateController из TSD).
sealed class UpdateState {
  const UpdateState();
}

/// Пусто: проверка ещё не шла / обновлений нет.
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

/// Есть обновление. [manifest] — что доступно.
class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.manifest);

  final VersionManifest manifest;
}

/// Скачивание APK. [progress] 0.0..1.0 (null, если длина неизвестна).
class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.progress);

  final double? progress;
}

/// APK скачан, системный установщик запущен.
class UpdateInstalling extends UpdateState {
  const UpdateInstalling();
}

/// Ошибка скачивания. [message] — для UI.
class UpdateError extends UpdateState {
  const UpdateError(this.message);

  final String message;
}

/// Контроллер автообновления: проверяет манифест, качает APK,
/// запускает системный установщик.
class UpdateController extends ChangeNotifier {
  UpdateController({UpdateRepository? repo, ApkInstaller? installer})
      : _repo = repo ?? UpdateRepository(),
        _installer = installer ?? ApkInstaller();

  final UpdateRepository _repo;
  final ApkInstaller _installer;

  UpdateState state = const UpdateIdle();

  /// Проверить наличие обновления (тихо: ошибки не показываем).
  /// Не запускается повторно, пока проверка/обновление уже активны.
  Future<void> checkForUpdate() async {
    if (state is! UpdateIdle && state is! UpdateError) return;

    final manifest = await _repo.checkForUpdate();
    if (manifest == null) {
      // Манифест недоступен/битый — молча остаёмся в прежнем состоянии.
      if (state is UpdateError) {
        state = const UpdateIdle();
        notifyListeners();
      }
      return;
    }

    final current = await _currentVersionCode();
    final hasUpdate = manifest.isNewerThan(current);
    debugPrint(
      'UPDATE: manifest=${manifest.versionCode} current=$current '
      '→ ${hasUpdate ? 'доступно обновление' : 'актуальная версия'}',
    );
    if (!hasUpdate) {
      state = const UpdateIdle();
      notifyListeners();
      return;
    }
    state = UpdateAvailable(manifest);
    notifyListeners();
  }

  /// Скачать APK и запустить системный установщик.
  Future<void> downloadAndInstall() async {
    final s = state;
    if (s is! UpdateAvailable) return;

    state = const UpdateDownloading(null);
    notifyListeners();

    try {
      final apk = await _repo.downloadApk(
        s.manifest,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : null;
          state = UpdateDownloading(progress);
          notifyListeners();
        },
      );
      state = const UpdateInstalling();
      notifyListeners();
      await _installer.installApk(apk);
      // После запуска установщика оператор подтверждает установку в системном
      // диалоге; сюда вернёмся уже новой версией после перезапуска.
    } on UpdateException catch (e) {
      state = UpdateError(e.message);
      notifyListeners();
    } catch (e) {
      state = const UpdateError('Не удалось скачать обновление.');
      notifyListeners();
    }
  }

  /// Сброс к idle (кнопка «Позже»).
  void skip() {
    state = const UpdateIdle();
    notifyListeners();
  }

  /// Повторить после ошибки.
  Future<void> retry() async {
    if (state is! UpdateError) return;
    state = const UpdateIdle();
    notifyListeners();
    await checkForUpdate();
  }

  /// Свой versionCode через package_info_plus.
  static Future<int> _currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }
}

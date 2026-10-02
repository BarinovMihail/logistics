import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Скачано, но система не даёт ставить: нужно разрешение «установка
/// неизвестных приложений». Диалог направляет в настройки.
class UpdateNeedsPermission extends UpdateState {
  const UpdateNeedsPermission(this.manifest);

  final VersionManifest manifest;
}

/// Ошибка скачивания. [message] — для UI.
class UpdateError extends UpdateState {
  const UpdateError(this.message);

  final String message;
}

/// Контроллер автообновления: проверяет манифест, качает APK,
/// запускает системный установщик.
class UpdateController extends ChangeNotifier {
  /// Ключ в SharedPreferences: versionCode версии, которую установщик должен
  /// поставить. После перезапуска приложения экран входа сравнит его с
  /// фактической версией: совпало — обновление удалось, возможен автологин
  /// под запомненной учёткой сразу в список заявок (флаг разовый).
  static const String pendingVersionKey = 'update_pending_version';

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
      // Запоминаем, какую версию ставим: после перезапуска экран входа
      // сверирует её с фактической и при совпадении войдёт автоматически.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(pendingVersionKey, s.manifest.versionCode);
      try {
        await _installer.installApk(apk);
        // После запуска установщика оператор подтверждает установку в системном
        // диалоге; сюда вернёмся уже новой версией после перезапуска.
      } on PlatformException catch (e) {
        if (e.code == 'no_installer') {
          // Система не разрешила ставить APK: отправляем в настройки
          // «установка неизвестных приложений» — это разовое действие.
          state = UpdateNeedsPermission(s.manifest);
          notifyListeners();
          await _installer.openInstallPermissionSettings();
        } else {
          state = UpdateError('Не удалось запустить установку: ${e.message}');
          notifyListeners();
        }
      }
    } on UpdateException catch (e) {
      state = UpdateError(e.message);
      notifyListeners();
    } catch (e) {
      state = const UpdateError('Не удалось скачать обновление.');
      notifyListeners();
    }
  }

  /// Повторить установку после выдачи разрешения в настройках.
  Future<void> retryInstall() async {
    final s = state;
    if (s is! UpdateNeedsPermission) return;
    state = UpdateAvailable(s.manifest);
    notifyListeners();
    await downloadAndInstall();
  }

  /// Открыть системные настройки «Установка неизвестных приложений».
  Future<void> openInstallPermissionSettings() =>
      _installer.openInstallPermissionSettings();

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

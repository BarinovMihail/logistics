import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge к нативному установщику APK (Kotlin MethodChannel).
///
/// Канал: `com.example.logistics/installer`, метод `installApk(path)`.
/// Нативная сторона (MainActivity.kt) получает content-URI через FileProvider
/// и запускает системный установщик (ACTION_VIEW).
class ApkInstaller {
  static const _channel = MethodChannel('com.example.logistics/installer');

  /// Передать [apk] системному установщику.
  /// Бросает [PlatformException], если нативная сторона не смогла
  /// (файл не существует, нет permission, подпись не совпала).
  Future<void> installApk(File apk) async {
    await _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }
}

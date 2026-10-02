package com.example.logistics

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.logistics/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "Не передан путь к APK", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (e: ActivityNotFoundException) {
                            // Обычно значит: приложение не имеет права ставить
                            // APK (Android 8+ «установка неизвестных
                            // приложений»), а прошивка не показывает запрос.
                            result.error(
                                "no_installer",
                                "Нет разрешения на установку приложений",
                                null
                            )
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    "openInstallPermissionSettings" -> {
                        try {
                            openInstallPermissionSettings()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Открыть системные настройки «Установка неизвестных приложений»
    /// для этого приложения — чтобы пользователь выдал разрешение.
    private fun openInstallPermissionSettings() {
        val uri = Uri.parse("package:$packageName")
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    /// Запуск системного установщика APK (для автообновления с Яндекс Диска).
    /// Файл передаётся через FileProvider (content:// URI). APK должен быть
    /// подписан тем же ключом, что и установленное приложение.
    private fun installApk(path: String) {
        val file = File(path)
        val authority = "${packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(this, authority, file)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}

/// Манифест версии: описание доступного обновления.
///
/// Контракт JSON (файл `manifest.json` в публичной папке Яндекс Диска):
/// ```json
/// {
///   "versionName": "1.0.1",
///   "versionCode": 2,
///   "apkPath": "releases/perevozka-1.0.1-2.apk",
///   "sha256": "<sha256 APK в нижнем регистре>",
///   "releaseNotes": "Что нового",
///   "required": false
/// }
/// ```
///
/// [apkPath] — путь к файлу относительно публичной папки Диска. Поддерживаются
/// `.apk` (готовый файл) и `.zip` (архив с APK — приложение распаковывает).
/// Сравнение версий идёт по целочисленному [versionCode] (монотонно растёт),
/// а не по строке versionName.
class VersionManifest {
  const VersionManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkPath,
    required this.releaseNotes,
    required this.sha256,
    required this.required,
  });

  /// Целочисленный код версии (из pubspec: «1.0.1+2» → 2). Монотонно растёт.
  final int versionCode;

  /// Человекочитаемая версия («1.0.1»). Только для отображения.
  final String versionName;

  /// Путь к APK (или zip с APK) относительно публичной папки Диска.
  final String apkPath;

  /// Текст изменений (примечание релиза). Показывается в диалоге.
  final String releaseNotes;

  /// SHA-256 APK в нижнем регистре. Пустая строка → манифест невалиден.
  final String sha256;

  /// Обязательное обновление: true → нельзя пропустить/закрыть диалог.
  final bool required;

  /// Достаточен ли манифест для установки: apkPath и sha256 непусты.
  bool get isValid => apkPath.isNotEmpty && sha256.isNotEmpty;

  /// Парсинг из JSON. Поля с невалидным типом заменяются значениями по
  /// умолчанию, чтобы битый манифест не ронял приложение.
  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      versionCode: _tryInt(json['versionCode']) ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      apkPath: (json['apkPath'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString(),
      required: json['required'] == true,
    );
  }

  /// Доступно ли обновление: манифест новее текущей установленной версии.
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// Безопасное приведение к int (манифест может содержать «8» или 8).
  static int? _tryInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}

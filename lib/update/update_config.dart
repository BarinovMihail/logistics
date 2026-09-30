/// Конфигурация источника автообновления на Яндекс Диске.
///
/// Приложение обращается к **публичным** эндпоинтам REST API Яндекс Диска,
/// которые не требуют OAuth-токена. Для этого корневая папка с обновлениями
/// (где лежат `manifest.json` и каталог `releases/`) должна быть опубликована
/// в Диске: «Поделиться» → «доступ по ссылке» (публичная). Публичная ссылка
/// имеет вид `https://disk.yandex.ru/d/XXXX` — именно её нужно подставить в
/// [UpdateConfig.publicKey].
///
/// APK не является секретом, поэтому публичный доступ к папке безопасен.
/// OAuth-токен используется **только** в скрипте публикации
/// (`scripts/publish-release.ps1`), но не в самом приложении.
class UpdateConfig {
  const UpdateConfig({
    required this.publicKey,
    required this.manifestPath,
    required this.apiBase,
  });

  /// Публичная ссылка на папку с обновлениями (`https://disk.yandex.ru/d/XXXX`).
  final String publicKey;

  /// Путь к манифесту версий относительно публичной папки (`manifest.json`).
  final String manifestPath;

  /// Базовый URL REST API Яндекс Диска.
  final String apiBase;
}

/// Источник обновлений: публичная папка Яндекс Диска
/// «APK NO DELETE/Логистика» (опубликована «доступ по ссылке»).
const kUpdateConfig = UpdateConfig(
  publicKey: 'https://disk.yandex.ru/d/sfYHlEtcA-CJxQ',
  manifestPath: 'manifest.json',
  apiBase: 'https://cloud-api.yandex.net/v1/disk',
);

/// Модель заявки на внутризаводскую перевозку (данные из 1С:ERP).
///
/// Ключи входного JSON — русские (так их отдаёт HTTP-сервис 1С), значения —
/// представления из 1С (в основном строки), поэтому каждое поле читается
/// через безопасные помощники внизу файла.
class TransportRequest {
  const TransportRequest({
    required this.number,
    required this.status,
    required this.item,
    required this.kkm,
    required this.quantity,
    required this.subdivision,
    required this.from,
    required this.to,
    required this.requiresPhoto,
    required this.requiresMaster,
    this.date,
    this.specialConditions,
    this.executor,
    this.takenAt,
    this.completedAt,
  });

  factory TransportRequest.fromJson(Map<String, dynamic> json) =>
      TransportRequest(
        number: _string(json['Номер']),
        date: _date(json['Дата']),
        status: _string(json['Статус']),
        item: _string(json['Изделие']),
        kkm: _string(json['ККМ']),
        quantity: _int(json['Количество']),
        subdivision: _string(json['Подразделение']),
        from: _string(json['Откуда']),
        to: _string(json['Куда']),
        requiresPhoto: _bool(json['ТребуетсяФото']),
        requiresMaster: _bool(json['ТребуетсяМастер']),
        specialConditions: _optionalString(json['ОсобыеУсловия']),
        executor: _optionalString(json['Исполнитель']),
        takenAt: _date(json['ДатаВзятияВРаботу']),
        completedAt: _date(json['ДатаВыполнения']),
      );

  /// «Номер» — например, «000000007».
  final String number;

  /// «Дата» — дата создания заявки.
  final DateTime? date;

  /// «Статус» — например, «На проверке диспетчера».
  final String status;

  /// «Изделие» — наименование и обозначение груза.
  final String item;

  /// «ККМ».
  final String kkm;

  /// «Количество», шт.
  final int quantity;

  /// «Подразделение» — цех/участок-инициатор заявки. Может отсутствовать
  /// в ответе сервера (поле добавляется в API) — тогда пустая строка.
  final String subdivision;

  /// «Откуда» — место погрузки.
  final String from;

  /// «Куда» — место выгрузки.
  final String to;

  /// «ТребуетсяФото».
  final bool requiresPhoto;

  /// «ТребуетсяМастер».
  final bool requiresMaster;

  /// «ОсобыеУсловия» — заполняется только в карточке заявки.
  final String? specialConditions;

  /// «Исполнитель» — заполняется только в карточке заявки.
  final String? executor;

  /// «ДатаВзятияВРаботу» — заполняется только в карточке заявки.
  final DateTime? takenAt;

  /// «ДатаВыполнения» — заполняется только в карточке заявки.
  final DateTime? completedAt;

  /// «Откуда» для отображения: пустое значение показываем как «—».
  String get fromDisplay => from.isEmpty ? '—' : from;

  /// «Куда» для отображения: пустое значение показываем как «—».
  String get toDisplay => to.isEmpty ? '—' : to;

  // --- Безопасное чтение значений из JSON 1С ---

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  /// Строка или null: пустое значение 1С («») — это null.
  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Число: реально приходит и числом, и строкой («25»).
  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    switch (value?.toString().toLowerCase()) {
      case 'true':
      case 'да':
      case 'истина':
      case '1':
        return true;
      default:
        return false;
    }
  }

  /// Даты из 1С приходят в виде «дд.ММ.гггг ч:мм:сс» (час может быть без
  /// ведущего нуля) или в ISO («2026-09-09T12:00:00»). Пустая дата 1С —
  /// «01.01.0001 0:00:00» / «0001-01-01T00:00:00» — превращается в null
  /// и на экране отображается как «—».
  static DateTime? _date(dynamic value) {
    final raw = _optionalString(value);
    if (raw == null) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return _dropIfEmpty1C(iso);

    final match = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(raw);
    if (match != null) {
      final parsed = DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
        int.parse(match.group(4) ?? '0'),
        int.parse(match.group(5) ?? '0'),
        int.parse(match.group(6) ?? '0'),
      );
      return _dropIfEmpty1C(parsed);
    }
    return null;
  }

  /// «Пустая» дата 1С имеет год 1 — приравниваем её к null.
  static DateTime? _dropIfEmpty1C(DateTime date) =>
      date.year < 1900 ? null : date;
}

/// Формат даты для отображения на экранах; null (пустая дата) — «—».
String formatDate(DateTime? date) {
  if (date == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

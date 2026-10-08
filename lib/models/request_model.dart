/// Модель заявки на внутризаводскую перевозку (данные из 1С:ERP).
///
/// Ключи входного JSON — русские (так их отдаёт HTTP-сервис 1С), значения —
/// представления из 1С, поэтому каждое поле читается через безопасные
/// помощники внизу файла.
///
/// Заявка содержит несколько операций перевозки. Список `/requests` отдаёт
/// сводку по заявке («Операций», суммарное «Количество»), карточка
/// `/requests/{Номер}` — полный массив «Операции».
library;

/// Формат даты для отображения на экранах; null (пустая дата) — «—».
String formatDate(DateTime? date) {
  if (date == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// Одна операция (строка) заявки на перевозку.
class RequestOperation {
  const RequestOperation({
    required this.lineNumber,
    required this.productionOrder,
    required this.routeSheet,
    required this.operationNumber,
    required this.nextOperationNumber,
    required this.techOperation,
    required this.kkm,
    required this.item,
    required this.quantity,
    required this.from,
    required this.to,
  });

  factory RequestOperation.fromJson(Map<String, dynamic> json) =>
      RequestOperation(
        lineNumber: _int(json['НомерСтроки']),
        productionOrder: _string(json['ПЗ']),
        routeSheet: _string(json['МаршрутныйЛист']),
        operationNumber: _int(json['НомерОперации']),
        nextOperationNumber: _int(json['НомерСледующейОперации']),
        techOperation: _string(json['ТехнологическаяОперация']),
        kkm: _string(json['ККМ']),
        item: _string(json['Номенклатура']),
        quantity: _int(json['Количество']),
        from: _string(json['Откуда']),
        to: _string(json['Куда']),
      );

  /// «НомерСтроки» — номер строки в заявке.
  final int lineNumber;

  /// «ПЗ» — производственное задание (представление документа).
  final String productionOrder;

  /// «МаршрутныйЛист» — представление документа.
  final String routeSheet;

  /// «НомерОперации» — номер операции техпроцесса.
  final int operationNumber;

  /// «НомерСледующейОперации».
  final int nextOperationNumber;

  /// «ТехнологическаяОперация» — например,
  /// «Цех 3,Токарная с ЧПУ,Наладчик станков с чпу,4,3».
  final String techOperation;

  /// «ККМ».
  final String kkm;

  /// «Номенклатура» — груз операции.
  final String item;

  /// «Количество», шт.
  final int quantity;

  /// «Откуда» — место погрузки.
  final String from;

  /// «Куда» — место выгрузки.
  final String to;

  /// «Откуда» для отображения: пустое значение показываем как «—».
  String get fromDisplay => from.isEmpty ? '—' : from;

  /// «Куда» для отображения: пустое значение показываем как «—».
  String get toDisplay => to.isEmpty ? '—' : to;
}

class TransportRequest {
  const TransportRequest({
    required this.number,
    required this.status,
    required this.subdivision,
    required this.transport,
    required this.vehicleKind,
    required this.requiresPhoto,
    required this.requiresMaster,
    required this.operations,
    this.date,
    this.quantity,
    this.declaredOperationsCount,
    this.specialConditions,
    this.hasSpecialConditions = false,
    this.executor,
    this.master = '',
    this.confirmedByMaster = false,
    this.takenAt,
    this.completedAt,
  });

  factory TransportRequest.fromJson(Map<String, dynamic> json) =>
      TransportRequest(
        number: _string(json['Номер']),
        date: _date(json['Дата']),
        status: _string(json['Статус']),
        subdivision: _string(json['Подразделение']),
        transport: _string(json['Транспорт']),
        vehicleKind: _string(json['ВидТранспорта']),
        requiresPhoto: _bool(json['ТребуетсяФото']),
        requiresMaster: _bool(json['ТребуетсяМастер']),
        operations: _operations(json['Операции']),
        quantity: _optionalInt(json['Количество']),
        declaredOperationsCount: _optionalInt(json['Операций']),
        specialConditions: _conditionsText(json['ОсобыеУсловия']),
        hasSpecialConditions: _hasConditions(json['ОсобыеУсловия']),
        executor: _optionalString(json['Исполнитель']),
        master: _string(json['Мастер']),
        confirmedByMaster: _bool(json['ПодтвержденоМастером']),
        takenAt: _date(json['ДатаВзятияВРаботу']),
        completedAt: _date(json['ДатаВыполнения']),
      );

  /// «Номер» — например, «000000034».
  final String number;

  /// «Дата» — дата создания заявки.
  final DateTime? date;

  /// «Статус» — например, «Готова к выполнению».
  final String status;

  /// «Подразделение» — цех/участок-инициатор заявки.
  final String subdivision;

  /// «Транспорт» — транспортное средство (например, «2515нв53»).
  /// Приходит в списке заявок; пустая строка — не назначен.
  final String transport;

  /// «ВидТранспорта» — требуемый вид ТС («Рохля», «Каток»…).
  /// Приходит в списке заявок; по нему открывается выбор конкретного ТС.
  final String vehicleKind;

  /// Слитная форма вида ТС: «Вилочный погрузчик» → «ВилочныйПогрузчик».
  /// Используется для отображения и запроса списка ТС по виду.
  String get vehicleKindJoined {
    final words =
        vehicleKind.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    var result = '';
    var first = true;
    for (final word in words) {
      if (first) {
        result = word;
        first = false;
      } else {
        result += word[0].toUpperCase() + word.substring(1);
      }
    }
    return result;
  }

  /// «ТребуетсяФото».
  final bool requiresPhoto;

  /// «ТребуетсяМастер».
  final bool requiresMaster;

  /// «Операции» — строки заявки. Отдаются только карточкой заявки.
  final List<RequestOperation> operations;

  /// «Количество» в шапке — суммарное по операциям (отдаёт список).
  final int? quantity;

  /// «Операций» в шапке — количество операций (отдаёт список).
  final int? declaredOperationsCount;

  /// «ОсобыеУсловия» — заполняется только в карточке заявки (текст условий).
  final String? specialConditions;

  /// Есть ли особые условия. В списке «ОсобыеУсловия» приходит булевым
  /// (true/false), в карточке — текстом (непустой текст = есть условия).
  final bool hasSpecialConditions;

  /// «Исполнитель» — заполняется только в карточке заявки.
  final String? executor;

  /// «Мастер» — кто должен подтвердить выполнение (карточка заявки).
  final String master;

  /// «ПодтвержденоМастером» (карточка заявки).
  final bool confirmedByMaster;

  /// «ДатаВзятияВРаботу» — заполняется только в карточке заявки.
  final DateTime? takenAt;

  /// «ДатаВыполнения» — заполняется только в карточке заявки.
  final DateTime? completedAt;

  /// Первая операция или null (в списке операций нет).
  RequestOperation? get firstOperation =>
      operations.isEmpty ? null : operations.first;

  /// Количество операций: из шапки списка, иначе по факту из карточки.
  int get operationsCount =>
      declaredOperationsCount ?? operations.length;

  /// Суммарное количество, шт: из шапки списка, иначе сумма по операциям.
  int get totalQuantity =>
      quantity ?? operations.fold(0, (sum, op) => sum + op.quantity);

  /// Заявка взята в работу исполнителем (доступно «Выполнено»).
  bool get isInWork => status == 'В работе';

  /// Готова к выполнению — можно выбрать ТС и взять в работу.
  bool get isReadyForExecution => status == 'Готова к выполнению';

  /// Выполнена исполнителем, ждёт подтверждения мастера.
  bool get isWaitingMaster => status == 'Ожидает подтверждения мастера';
}

// --- Безопасное чтение значений из JSON 1С ---

String _string(dynamic value) => value?.toString().trim() ?? '';

/// Строка или null: пустое значение 1С («») — это null.
String? _optionalString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Число: реально приходит и числом, и строкой («25»).
int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Число или null — для необязательных полей шапки (в карточке их нет).
int? _optionalInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

bool _bool(dynamic value) {
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
DateTime? _date(dynamic value) {
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
DateTime? _dropIfEmpty1C(DateTime date) => date.year < 1900 ? null : date;

/// Массив «Операции»: отсутствующий/сломанный элемент пропускаем.
List<RequestOperation> _operations(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(RequestOperation.fromJson)
      .toList();
}

/// Текст особых условий: булево значение (список) текстом не является.
String? _conditionsText(dynamic value) =>
    value is String ? _optionalString(value) : null;

/// Признак «есть особые условия»: true для bool true; для текста —
/// непустая строка (кроме «нет»/«false»).
bool _hasConditions(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is! String) return false;
  final text = value.trim().toLowerCase();
  return text.isNotEmpty && text != 'нет' && text != 'false' && text != '0';
}

/// Ошибка взаимодействия с HTTP-сервисом 1С:ERP.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// Понятное пользователю сообщение на русском языке.
  final String message;

  /// HTTP-код ответа, если он был.
  final int? statusCode;

  @override
  String toString() => message;
}

/// 401 — неверный логин/пароль либо сохранённые учётные данные
/// перестали действовать. Реакция приложения — вернуться на экран входа.
class UnauthorizedException extends ApiException {
  const UnauthorizedException([
    super.message = 'Требуется вход в систему',
  ]) : super(statusCode: 401);
}

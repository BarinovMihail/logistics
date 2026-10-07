import 'package:flutter/material.dart';

import '../models/request_model.dart';
import 'status_badge.dart';

/// Карточка заявки в списке (экран 1).
///
/// Список `/requests` отдаёт сводку по заявке (без состава операций):
/// номер, дата, статус, подразделение, количество операций, суммарное
/// количество и требования. Детальный состав операций — на экране карточки.
///
/// Шапка карточки: бейдж статуса и индикаторы требований (📷 требуется фото,
/// 👤 нужен мастер, ⚠ особые условия) справа от него; ниже — номер заявки
/// с датой, сводка операций и транспорт.
///
/// [isCurrentTask] — заявка «В работе» у вошедшего пользователя: поднимается
/// в начало списка и помечается чипом «★ ТЕКУЩАЯ ЗАДАЧА».
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.onTap,
    this.isCurrentTask = false,
  });

  final TransportRequest request;
  final VoidCallback onTap;
  final bool isCurrentTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multi = request.operationsCount > 1;

    final summary = <String>[
      if (request.operationsCount > 0)
        'Операций: ${request.operationsCount}',
      if (request.totalQuantity > 0)
        '${multi ? 'Всего: ' : ''}${request.totalQuantity} шт',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Статус + индикаторы требований справа от него.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isCurrentTask)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B), // бирюзовый — не как статусы
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '★ ТЕКУЩАЯ ЗАДАЧА',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  StatusBadge(status: request.status),
                  if (request.requiresPhoto) _indicator(theme, '📷'),
                  if (request.requiresMaster) _indicator(theme, '👤'),
                  if (request.hasSpecialConditions) _indicator(theme, '⚠'),
                ],
              ),
              const SizedBox(height: 10),
              // Номер заявки и дата создания на одной строке.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Заявка № ${request.number}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatDate(request.date),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '🚛 Транспорт: ${request.transport.isEmpty ? 'не указан' : request.transport}',
                style: theme.textTheme.bodyLarge,
              ),
              if (request.subdivision.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('🏢 ${request.subdivision}',
                    style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Компактный индикатор требования рядом со статусом.
  Widget _indicator(ThemeData theme, String emoji) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 15)),
      );
}

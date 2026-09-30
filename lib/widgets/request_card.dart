import 'package:flutter/material.dart';

import '../models/request_model.dart';
import 'status_badge.dart';

/// Карточка заявки в списке (экран 1).
///
/// Список `/requests` отдаёт сводку по заявке (без состава операций):
/// номер, дата, статус, подразделение, количество операций, суммарное
/// количество и требования. Детальный состав операций — на экране карточки.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, required this.onTap});

  final TransportRequest request;
  final VoidCallback onTap;

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

    final meta = <String>[
      if (request.requiresPhoto) '📷 требуется фото',
      if (request.requiresMaster) '👤 нужен мастер',
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
              StatusBadge(status: request.status),
              const SizedBox(height: 10),
              Text(
                'Заявка № ${request.number}',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
              if (request.subdivision.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('🏢 ${request.subdivision}',
                    style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 6),
              Text(
                '🚛 Транспорт: ${request.transport.isEmpty ? 'не указан' : request.transport}',
                style: theme.textTheme.bodyLarge,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                formatDate(request.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

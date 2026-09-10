import 'package:flutter/material.dart';

import '../models/request_model.dart';
import 'status_badge.dart';

/// Карточка заявки в списке (экран 1).
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, required this.onTap});

  final TransportRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Четвёртая строка: «30 шт · 📷 требуется фото · 👤 нужен мастер».
    final meta = <String>[
      '${request.quantity} шт',
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
                request.item,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text('ККМ: ${request.kkm}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 6),
              Text(
                '📍 ${request.fromDisplay}  →  📍 ${request.toDisplay}',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Text(
                meta,
                style: theme.textTheme.bodyMedium?.copyWith(
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

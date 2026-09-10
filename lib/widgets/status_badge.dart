import 'package:flutter/material.dart';

/// Цветной бейдж со статусом заявки.
///
/// Цвет по статусу:
///  • «На проверке диспетчера» — голубой;
///  • «В работе» — синий;
///  • «Ожидает подтверждения мастера» — оранжевый;
///  • «Готова к выполнению» — зелёный;
///  • прочие статусы (например, «На решении руководителя») — серый.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  static const Map<String, Color> _colors = {
    'На проверке диспетчера': Color(0xFF039BE5), // голубой
    'В работе': Color(0xFF1565C0), // синий
    'Ожидает подтверждения мастера': Color(0xFFEF6C00), // оранжевый
    'Готова к выполнению': Color(0xFF2E7D32), // зелёный
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? const Color(0xFF616161);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

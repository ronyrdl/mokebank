import 'rate_format.dart';

import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';

import '../../themes/app_colors.dart';
import 'record_dialog.dart';
import 'bank_widgets.dart';

String movementTitle(Json row) => switch (row['type']) {
  'TRANSFER' => 'Transferencia',
  'WITHDRAW' => 'Retiro',
  'DEPOSIT' => 'Depósito',
  _ => 'Movimiento',
};

Map<String, Object?> movementFields(Json row) => {
  'Estado': movementStatus(row['status']),
  'Monto':
      '${row['original_amount']} ${row['source_currency'] ?? row['destination_currency'] ?? ''}',
  'Comisión': row['fee'],
  if (row['exchange_rate'] != null)
    'Tasa de cambio': formatExchangeRate(row['exchange_rate']),
  if (row['converted_amount'] != null)
    'Monto convertido':
        '${row['converted_amount']} ${row['destination_currency']}',
  'Fecha': _movementDate(row['created_at']),
  'Referencia': row['id'],
  if (row['failure_code'] != null) 'Motivo': row['failure_code'],
};

String movementStatus(Object? status) => switch (status) {
  'COMPLETED' => 'Completada',
  'PENDING' => 'Pendiente',
  'FAILED' => 'Fallida',
  _ => 'Sin estado',
};

String _movementDate(Object? timestamp) {
  if (timestamp is! String) return '—';
  final local = DateTime.tryParse(timestamp)?.toLocal();
  if (local == null) return '—';
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Widget movementTile(BuildContext context, Json row) {
  final type = row['type'];
  final completed = row['status'] == 'COMPLETED';
  final incoming = type == 'DEPOSIT';
  final dateLabel = _movementDate(row['created_at']);
  final currency = row['source_currency'] ?? row['destination_currency'] ?? '';
  final chargedFee = completed && (num.tryParse('${row['fee']}') ?? 0) > 0;
  final converted =
      completed &&
      row['converted_amount'] != null &&
      row['source_currency'] != null &&
      row['destination_currency'] != null &&
      row['source_currency'] != row['destination_currency'];
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: incoming ? fondoVerdeSuave : superficieIconos,
      foregroundColor: incoming ? confirmacion : naranja,
      child: Icon(switch (type) {
        'DEPOSIT' => Icons.south_west,
        'WITHDRAW' => Icons.north_east,
        _ => Icons.swap_horiz,
      }, size: 19),
    ),
    title: Text(
      movementTitle(row),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$dateLabel · ${movementStatus(row['status'])}',
          style: const TextStyle(color: textoSecundario50, fontSize: 12),
        ),
        if (chargedFee || converted)
          Wrap(
            spacing: 6,
            children: [
              if (chargedFee) const StatusLabel('Comisión', color: naranja),
              if (converted)
                const StatusLabel('Conversión', color: informacion),
            ],
          ),
      ],
    ),
    trailing: Text(
      '${row['original_amount']} $currency',
      style: TextStyle(
        color: incoming && completed ? confirmacion : textoPrincipal,
      ),
    ),
    onTap: () =>
        showRecord(context, 'Detalle del movimiento', movementFields(row)),
  );
}

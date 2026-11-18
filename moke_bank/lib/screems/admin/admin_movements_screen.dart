import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';
import 'package:moke_bank/screems/shared/movements_screen.dart';
import 'package:moke_bank/screems/shared/movement_details.dart';
import 'package:moke_bank/services/transactions_service.dart';

class AdminMovementsScreen extends StatelessWidget {
  const AdminMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 100,
        child: BankLoader<List<Json>>(
          load: const TransactionsService().stats,
          builder: (data, _) => Center(
            child: Wrap(
              spacing: 8,
              children: [
                for (final row in data.where(
                  (row) => row['status'] == 'COMPLETED',
                ))
                  Chip(label: Text('${movementTitle(row)} · ${row['count']}')),
              ],
            ),
          ),
        ),
      ),
      const Expanded(child: Movements()),
    ],
  );
}

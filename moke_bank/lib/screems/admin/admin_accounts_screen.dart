import 'package:flutter/material.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

import 'new_account_dialog.dart';
import 'account_status_dialog.dart';

import 'package:moke_bank/services/accounts_service.dart';
import 'package:moke_bank/services/clients_service.dart';

class AdminAccountsScreen extends StatelessWidget {
  const AdminAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => BankLoader(
    load: () async => (
      await const AccountsService().list(),
      await const ClientsService().list(),
    ),
    builder: (data, reload) {
      final clients = {for (final user in data.$2) user['id']: user};
      final active = data.$2
          .where((user) => user['role'] == 'CLIENT' && user['active'] == true)
          .toList();
      return BankPage(
        title: 'Cuentas',
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: active.isEmpty
                  ? null
                  : () async {
                      if (await showNewAccount(context, active) &&
                          context.mounted) {
                        reload();
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('Abrir cuenta'),
            ),
          ),
          const SizedBox(height: 12),
          if (data.$1.isEmpty)
            const Text('Todavía no hay cuentas en este banco.'),
          for (final row in data.$1)
            Card(
              child: ListTile(
                title: Text(accountLabel(row)),
                subtitle: Text(
                  '${clients[row['owner_id']] != null ? fullName(clients[row['owner_id']]!) : 'Titular'} · ${row['status']}',
                ),
                trailing: Text('${row['balance']}'),
                onTap: () async {
                  if (await showDialog<bool>(
                            context: context,
                            builder: (_) => AccountStatusDialog(account: row),
                          ) ==
                          true &&
                      context.mounted) {
                    reload();
                  }
                },
              ),
            ),
        ],
      );
    },
  );
}

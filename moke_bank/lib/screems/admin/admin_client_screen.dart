import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

import 'client_details_dialog.dart';
import 'new_client_dialog.dart';

import 'package:moke_bank/services/clients_service.dart';

class AdminClientScreen extends StatefulWidget {
  const AdminClientScreen({super.key});

  @override
  State<AdminClientScreen> createState() => _AdminClientScreenState();
}

class _AdminClientScreenState extends State<AdminClientScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) => BankLoader<List<Json>>(
    load: () => const ClientsService().list(),
    builder: (rows, reload) {
      final clients = rows.where(
        (user) =>
            user['role'] == 'CLIENT' &&
            '${fullName(user)} ${user['email']}'.toLowerCase().contains(
              _filter,
            ),
      );
      return BankPage(
        title: 'Clientes',
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                if (await showDialog<bool>(
                          context: context,
                          builder: (_) => const NewClientDialog(),
                        ) ==
                        true &&
                    context.mounted) {
                  reload();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo cliente'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre o correo',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _filter = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          if (clients.isEmpty) const Text('No se encontraron clientes.'),
          for (final client in clients)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(fullName(client)),
                subtitle: Text(
                  '${client['email']} · ${client['active'] == true ? 'Activo' : 'Inactivo'}',
                ),
                onTap: () async {
                  if (await showDialog<bool>(
                            context: context,
                            builder: (_) => ClientDetailsDialog(client: client),
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

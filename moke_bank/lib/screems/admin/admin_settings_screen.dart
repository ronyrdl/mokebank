import '../shared/rate_format.dart';

import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

import 'settings_form.dart';

import 'package:moke_bank/services/banks_service.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => BankLoader<Json>(
    load: () => const BanksService().config(),
    builder: (data, reload) => BankPage(
      title: 'Configuración',
      children: [
        ListTile(
          title: const Text('Moneda principal'),
          trailing: Text('${data['currency']}'),
        ),
        ListTile(
          title: const Text('Límite por transacción'),
          trailing: Text('${data['transaction_limit']}'),
        ),
        ListTile(
          title: const Text('Comisión fija'),
          trailing: Text('${data['fee_fixed']}'),
        ),
        ListTile(
          title: const Text('Comisión porcentual'),
          trailing: Text('${data['fee_percent']} %'),
        ),
        const Divider(),
        const Text('Tasas de cambio'),
        for (final rate in (data['rates'] as List).cast<Json>())
          ListTile(
            title: Text(
              '${rate['source_currency']} → ${rate['destination_currency']}',
            ),
            trailing: Text(formatExchangeRate(rate['rate'])),
          ),
        const Divider(),
        ListTile(
          title: const Text('Webhook'),
          subtitle: Text(
            data['webhook'] == null
                ? 'Sin configurar'
                : '${data['webhook']['url']}',
          ),
        ),
        OutlinedButton(
          onPressed: () async {
            if (await showDialog<bool>(
                      context: context,
                      builder: (_) => SettingsForm(data: data),
                    ) ==
                    true &&
                context.mounted) {
              reload();
            }
          },
          child: const Text('Editar configuración'),
        ),
      ],
    ),
  );
}

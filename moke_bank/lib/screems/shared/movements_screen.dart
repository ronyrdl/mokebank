import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';

import 'bank_widgets.dart';
import 'movement_details.dart';

import 'package:moke_bank/services/accounts_service.dart';
import 'package:moke_bank/services/transactions_service.dart';

class Movements extends StatefulWidget {
  const Movements({super.key});
  @override
  State<Movements> createState() => _MovementsState();
}

class _MovementsState extends State<Movements> {
  String _type = '';
  String _account = '';
  DateTimeRange? _dates;
  var _page = 1;

  @override
  Widget build(BuildContext context) => BankLoader<List<Json>>(
    load: () => const AccountsService().list(),
    builder: (accounts, _) => BankLoader<Json>(
      key: ValueKey((_type, _account, _dates, _page)),
      load: () => const TransactionsService().list(
        filters: {
          if (_type.isNotEmpty) 'type': _type,
          if (_account.isNotEmpty) 'account_id': _account,
          if (_dates case final dates?) ...{
            'from': dates.start.toUtc().toIso8601String(),
            'to': DateTime(dates.end.year, dates.end.month, dates.end.day + 1)
                .subtract(const Duration(milliseconds: 1))
                .toUtc()
                .toIso8601String(),
          },
          'page': '$_page',
          'limit': '20',
        },
      ),
      builder: (data, reload) => BankPage(
        title: 'Movimientos',
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Todos')),
              DropdownMenuItem(value: 'DEPOSIT', child: Text('Depósitos')),
              DropdownMenuItem(value: 'WITHDRAW', child: Text('Retiros')),
              DropdownMenuItem(
                value: 'TRANSFER',
                child: Text('Transferencias'),
              ),
            ],
            onChanged: (value) => setState(() {
              _type = value!;
              _page = 1;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _account,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Todas las cuentas'),
              ),
              for (final account in accounts)
                DropdownMenuItem(
                  value: account['id'] as String,
                  child: Text(accountLabel(account)),
                ),
            ],
            onChanged: (value) => setState(() {
              _account = value!;
              _page = 1;
            }),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () async {
                  final result = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDateRange: _dates,
                  );
                  if (mounted && result != null) {
                    setState(() {
                      _dates = result;
                      _page = 1;
                    });
                  }
                },
                child: Text(
                  _dates == null ? 'Filtrar fechas' : 'Cambiar fechas',
                ),
              ),
              if (_dates != null)
                TextButton(
                  onPressed: () => setState(() {
                    _dates = null;
                    _page = 1;
                  }),
                  child: const Text('Quitar fechas'),
                ),
            ],
          ),
          if ((data['items'] as List).isEmpty)
            const Text('No hay movimientos para estos filtros.'),
          for (final row in (data['items'] as List).cast<Json>())
            movementTile(context, row),
          Wrap(
            spacing: 8,
            children: [
              if (_page > 1)
                OutlinedButton(
                  onPressed: () => setState(() => _page--),
                  child: const Text('Anterior'),
                ),
              if (data['has_more'] == true)
                OutlinedButton(
                  onPressed: () => setState(() => _page++),
                  child: const Text('Siguiente'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';
import 'package:moke_bank/screems/shared/record_dialog.dart';
import 'package:moke_bank/services/accounts_service.dart';

Future<bool> showNewAccount(BuildContext context, List<Json> clients) async {
  final result = await showDialog<Json>(
    context: context,
    builder: (_) => _NewAccount(clients: clients),
  );
  if (result == null) return false;
  if (context.mounted) {
    await showRecord(context, 'Cuenta creada', {
      'Número de cuenta': result['number'],
      'Moneda': result['currency'],
      'Estado': result['status'],
    });
  }
  return true;
}

class _NewAccount extends StatefulWidget {
  const _NewAccount({required this.clients});
  final List<Json> clients;

  @override
  State<_NewAccount> createState() => _NewAccountState();
}

class _NewAccountState extends State<_NewAccount> {
  late String _owner = widget.clients.first['id'] as String;
  String _currency = 'COP';
  String? _error;
  bool _busy = false;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await const AccountsService().create(
        owner: _owner,
        currency: _currency,
      );
      if (mounted) Navigator.pop(context, result);
    } on ApiError catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Abrir cuenta'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _owner,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Titular'),
              items: [
                for (final user in widget.clients)
                  DropdownMenuItem(
                    value: user['id'] as String,
                    child: Text(
                      fullName(user),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _owner = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: [
                for (final currency in ['COP', 'USD', 'EUR'])
                  DropdownMenuItem(value: currency, child: Text(currency)),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _currency = value!),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: Text(_busy ? 'Creando…' : 'Crear cuenta'),
      ),
    ],
  );
}

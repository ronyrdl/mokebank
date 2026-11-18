import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';
import 'package:moke_bank/services/accounts_service.dart';

class AccountStatusDialog extends StatefulWidget {
  const AccountStatusDialog({super.key, required this.account});
  final Json account;
  @override
  State<AccountStatusDialog> createState() => _AccountStatusDialogState();
}

class _AccountStatusDialogState extends State<AccountStatusDialog> {
  late String _status = widget.account['status'] as String;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const AccountsService().setStatus(
        widget.account['id'] as String,
        _status,
      );
      if (mounted) Navigator.pop(context, true);
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
    title: Text(accountLabel(widget.account)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Saldo · ${widget.account['balance']} ${widget.account['currency']}',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: const [
            DropdownMenuItem(value: 'ACTIVE', child: Text('Activa')),
            DropdownMenuItem(value: 'INACTIVE', child: Text('Inactiva')),
            DropdownMenuItem(value: 'BLOCKED', child: Text('Bloqueada')),
          ],
          onChanged: _busy ? null : (value) => setState(() => _status = value!),
        ),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      FilledButton(
        onPressed: _busy || widget.account['status'] == _status ? null : _save,
        child: const Text('Guardar estado'),
      ),
    ],
  );
}

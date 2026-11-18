import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

import 'new_account_dialog.dart';

import 'package:moke_bank/services/clients_service.dart';

class ClientDetailsDialog extends StatefulWidget {
  const ClientDetailsDialog({super.key, required this.client});
  final Json client;

  @override
  State<ClientDetailsDialog> createState() => _ClientDetailsDialogState();
}

class _ClientDetailsDialogState extends State<ClientDetailsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _changeStatus() async {
    final active = widget.client['active'] == true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const ClientsService().setActive(
        widget.client['id'] as String,
        !active,
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
    title: Text(fullName(widget.client)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.client['email']}'),
        Text(auth.bankName),
        Text(widget.client['active'] == true ? 'Activo' : 'Inactivo'),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _changeStatus,
        child: Text(widget.client['active'] == true ? 'Desactivar' : 'Activar'),
      ),
      if (widget.client['active'] == true)
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  await showNewAccount(context, [widget.client]);
                },
          child: const Text('Abrir cuenta'),
        ),
    ],
  );
}

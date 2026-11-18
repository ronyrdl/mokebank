import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/services/clients_service.dart';

class NewClientDialog extends StatefulWidget {
  const NewClientDialog({super.key});
  @override
  State<NewClientDialog> createState() => _NewClientDialogState();
}

class _NewClientDialogState extends State<NewClientDialog> {
  final _form = GlobalKey<FormState>();
  static const labels = {
    'first_name': 'Nombre',
    'last_name': 'Apellido',
    'email': 'Correo electrónico',
    'password': 'Contraseña',
  };
  final _fields = {for (final key in labels.keys) key: TextEditingController()};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const ClientsService().create({
        for (final field in _fields.entries)
          field.key: field.key == 'password'
              ? field.value.text
              : field.value.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo cliente'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Banco asignado · ${auth.bankName}'),
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _fields[entry.key],
                    enabled: !_busy,
                    obscureText: entry.key == 'password',
                    decoration: InputDecoration(
                      labelText: entry.value,
                      errorMaxLines: 4,
                    ),
                    keyboardType: entry.key == 'email'
                        ? TextInputType.emailAddress
                        : null,
                    validator: (value) {
                      final text = value!.trim();
                      if (text.isEmpty) return 'Campo obligatorio';
                      if (entry.key == 'email' &&
                          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(text)) {
                        return 'Escribe un correo válido';
                      }
                      if (entry.key == 'password') {
                        if (value.runes.length < 12) {
                          return 'La contraseña debe tener al menos 12 caracteres.';
                        }
                        if (utf8.encode(value).length > 72) {
                          return 'La contraseña no puede superar los 72 bytes.';
                        }
                      }
                      return null;
                    },
                  ),
                ),
              if (_error != null) Text(_error!),
            ],
          ),
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
        child: Text(_busy ? 'Guardando…' : 'Guardar cliente'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/services/banks_service.dart';

class SettingsForm extends StatefulWidget {
  const SettingsForm({super.key, required this.data});
  final Json data;
  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  final _form = GlobalKey<FormState>();
  static const labels = {
    'transaction_limit': 'Límite por transacción',
    'fee_fixed': 'Comisión fija',
    'fee_percent': 'Comisión porcentual',
    'webhook_url': 'URL del webhook',
    'webhook_secret': 'Secreto del webhook',
  };
  late final _fields = {
    for (final key in labels.keys)
      key: TextEditingController(
        text:
            widget.data[key]?.toString() ??
            (key == 'webhook_url'
                ? ((widget.data['webhook'] as Json?)?['url'] as String?)
                : null),
      ),
  };
  late String _currency = widget.data['currency'] as String;
  late final _rates = {
    for (final source in ['COP', 'USD', 'EUR'])
      for (final target in ['COP', 'USD', 'EUR'])
        if (source != target)
          (source, target): TextEditingController(
            text: (widget.data['rates'] as List)
                .cast<Json>()
                .firstWhere(
                  (rate) =>
                      rate['source_currency'] == source &&
                      rate['destination_currency'] == target,
                  orElse: () => const {},
                )['rate']
                ?.toString(),
          ),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [..._fields.values, ..._rates.values]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final url = _fields['webhook_url']!.text.trim();
    final secret = _fields['webhook_secret']!.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const BanksService().updateConfig({
        'currency': _currency,
        for (final key in ['transaction_limit', 'fee_fixed', 'fee_percent'])
          key: _fields[key]!.text.trim().replaceAll(',', '.'),
        'rates': [
          for (final rate in _rates.entries)
            if (rate.value.text.trim().isNotEmpty)
              {
                'source_currency': rate.key.$1,
                'destination_currency': rate.key.$2,
                'rate': rate.value.text.trim().replaceAll(',', '.'),
              },
        ],
        if (secret.isNotEmpty) 'webhook': {'url': url, 'secret': secret},
      });
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
    title: const Text('Editar configuración'),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Moneda principal',
                ),
                items: [
                  for (final currency in ['COP', 'USD', 'EUR'])
                    DropdownMenuItem(value: currency, child: Text(currency)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _currency = value!),
              ),
              for (final key in labels.keys)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _fields[key],
                    enabled: !_busy,
                    obscureText: key == 'webhook_secret',
                    decoration: InputDecoration(labelText: labels[key]),
                    validator: (value) {
                      if (!key.startsWith('webhook_') &&
                          value!.trim().isEmpty) {
                        return 'Campo obligatorio';
                      }
                      if (key == 'webhook_url' &&
                          value!.trim() !=
                              (widget.data['webhook']?['url'] ?? '') &&
                          _fields['webhook_secret']!.text.isEmpty) {
                        return 'Escribe el secreto para cambiar la URL';
                      }
                      if (key == 'webhook_secret' &&
                          value!.isNotEmpty &&
                          value.length < 32) {
                        return 'Mínimo 32 caracteres';
                      }
                      return null;
                    },
                  ),
                ),
              for (final rate in _rates.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: rate.value,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'Tasa ${rate.key.$1} → ${rate.key.$2}',
                    ),
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
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Guardando…' : 'Guardar'),
      ),
    ],
  );
}

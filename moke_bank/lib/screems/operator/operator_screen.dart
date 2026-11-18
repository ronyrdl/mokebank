import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moke_bank/services/banks_service.dart';

import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

class OperatorScreen extends StatefulWidget {
  const OperatorScreen({super.key});
  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  static const _labels = {
    'platform': 'Clave de plataforma',
    'name': 'Nombre comercial',
    'slug': 'Identificador único',
    'transaction_limit': 'Límite por transacción',
    'fee_fixed': 'Comisión fija',
    'fee_percent': 'Comisión porcentual',
    'usd_cop': 'Tasa USD → COP',
    'cop_usd': 'Tasa COP → USD',
    'first_name': 'Nombre del administrador',
    'last_name': 'Apellido del administrador',
    'email': 'Correo del administrador',
    'password': 'Contraseña del administrador',
  };
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final field in _labels.keys) field: TextEditingController(),
  };
  String _currency = 'COP';
  Json? _bank;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();
  String _decimal(String key) => _value(key).replaceAll(',', '.');

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bank = await const BanksService().create(
        platformKey: _value('platform'),
        bank: {
          'name': _value('name'),
          'slug': _value('slug').toLowerCase(),
          'currency': _currency,
          for (final key in ['transaction_limit', 'fee_fixed', 'fee_percent'])
            key: _decimal(key),
          'rates': [
            if (_value('usd_cop').isNotEmpty)
              {
                'source_currency': 'USD',
                'destination_currency': 'COP',
                'rate': _decimal('usd_cop'),
              },
            if (_value('cop_usd').isNotEmpty)
              {
                'source_currency': 'COP',
                'destination_currency': 'USD',
                'rate': _decimal('cop_usd'),
              },
          ],
          'admin': {
            for (final key in ['first_name', 'last_name', 'email'])
              key: _value(key),
            'password': _fields['password']!.text,
          },
        },
      );
      if (!mounted) return;
      AuthService.banks[bank['slug'] as String] = bank['name'] as String;
      _fields['password']!.clear();
      _fields['platform']!.clear();
      setState(() => _bank = bank);
    } on ApiError catch (error) {
      if (mounted) {
        setState(
          () => _error = error.status == 409
              ? 'El identificador ya está en uso.'
              : error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Moke Bank · Operador de plataforma')),
    body: SafeArea(
      child: _bank != null
          ? BankPage(
              title: 'Banco creado',
              children: [
                ListTile(
                  title: Text('${_bank!['name']}'),
                  subtitle: Text('${_bank!['slug']}'),
                ),
                ListTile(
                  title: const Text('Administrador'),
                  subtitle: Text('${_bank!['admin']['email']}'),
                ),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Entrar como administrador'),
                ),
              ],
            )
          : Form(
              key: _form,
              child: BankPage(
                title: 'Crear nuevo banco',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Moneda principal',
                    ),
                    items: [
                      for (final currency in ['COP', 'USD', 'EUR'])
                        DropdownMenuItem(
                          value: currency,
                          child: Text(currency),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _currency = value!),
                  ),
                  for (final field in _labels.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: _fields[field.key],
                        enabled: !_busy,
                        obscureText: [
                          'platform',
                          'password',
                        ].contains(field.key),
                        decoration: InputDecoration(labelText: field.value),
                        validator: (value) {
                          if (['usd_cop', 'cop_usd'].contains(field.key)) {
                            return null;
                          }
                          if (value!.trim().isEmpty) return 'Campo obligatorio';
                          if (field.key == 'password' &&
                              value.runes.length < 12) {
                            return 'Usa al menos 12 caracteres';
                          }
                          return null;
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(
                      _busy ? 'Creando…' : 'Crear banco y administrador',
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

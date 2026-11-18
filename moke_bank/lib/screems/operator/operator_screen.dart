import 'dart:convert';

import 'platform_banks.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:moke_bank/services/banks_service.dart';

import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';

class OperatorScreen extends ConsumerStatefulWidget {
  const OperatorScreen({super.key});
  @override
  ConsumerState<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends ConsumerState<OperatorScreen> {
  static const _labels = {
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
  bool _showBanks = true;
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

  void _clearBank() {
    for (final field in _fields.values) {
      field.clear();
    }
    _bank = null;
    _error = null;
    _currency = 'COP';
  }

  Future<void> _create() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bank = await const BanksService().create(
        platformToken: ref.read(platformSessionProvider)!,
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
      ref.invalidate(bankDirectoryProvider);
      ref.invalidate(platformBanksProvider);
      setState(() => _bank = bank);
    } on ApiError catch (error) {
      if (mounted) {
        setState(() {
          if (error.status == 403) {
            ref.read(platformSessionProvider.notifier).logout();
            _clearBank();
            _error = 'Vuelve a iniciar sesión como superadmin.';
          } else {
            _error = error.status == 409
                ? 'El identificador ya está en uso.'
                : error.message;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCredentials() async {
    final bank = _bank!;
    final admin = bank['admin'] as Json;
    await Clipboard.setData(
      ClipboardData(
        text:
            'Banco: ${bank['name']}\n'
            'Identificador: ${bank['slug']}\n'
            'Correo: ${admin['email']}\n'
            'Contraseña: ${_fields['password']!.text}',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Credenciales copiadas. Compártelas por un canal privado.',
          ),
        ),
      );
    }
  }

  Widget _errorMessage(BuildContext context) => Text(
    _error!,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración de plataforma'),
        actions: [
          if (ref.watch(platformSessionProvider) != null)
            IconButton(
              tooltip: 'Cerrar acceso de plataforma',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      ref.read(platformSessionProvider.notifier).logout();
                      _clearBank();
                    }),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _showBanks ? 0 : 1,
        onDestinationSelected: _busy
            ? null
            : (index) => setState(() => _showBanks = index == 0),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            label: 'Bancos',
          ),
          NavigationDestination(icon: Icon(Icons.add), label: 'Crear banco'),
        ],
      ),
      body: SafeArea(
        child: _showBanks
            ? const PlatformBanks()
            : bank != null
            ? BankPage(
                title: 'Banco creado',
                children: [
                  ListTile(
                    title: Text('${bank['name']}'),
                    subtitle: Text('Identificador: ${bank['slug']}'),
                  ),
                  ListTile(
                    title: const Text('Administrador'),
                    subtitle: Text('${bank['admin']['email']}'),
                  ),
                  FilledButton(
                    onPressed: _copyCredentials,
                    child: const Text('Copiar credenciales del administrador'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(_clearBank),
                    child: const Text('Crear otro banco'),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(platformSessionProvider.notifier).logout();
                      context.go('/login?banco=${bank['slug']}');
                    },
                    child: const Text('Ir al ingreso del banco'),
                  ),
                ],
              )
            : Form(
                key: _form,
                child: BankPage(
                  title: 'Crear banco',
                  form: true,
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
                          obscureText: field.key == 'password',
                          decoration: InputDecoration(
                            labelText: field.value,
                            errorMaxLines: 3,
                          ),
                          validator: (value) {
                            if (['usd_cop', 'cop_usd'].contains(field.key)) {
                              return null;
                            }
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Campo obligatorio';
                            if (field.key == 'slug' &&
                                !RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$')
                                    .hasMatch(text.toLowerCase())) {
                              return 'Usa de 2 a 63 caracteres: letras, números o guiones.';
                            }
                            if (field.key == 'email' &&
                                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(text)) {
                              return 'Escribe un correo válido.';
                            }
                            if (field.key == 'password') {
                              if (value!.length < 12) {
                                return 'Usa al menos 12 caracteres.';
                              }
                              if (utf8.encode(value).length > 72) {
                                return 'Usa como máximo 72 bytes.';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (_error != null) _errorMessage(context),
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
}

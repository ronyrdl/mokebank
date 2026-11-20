import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/banks_service.dart';
import 'shared/bank_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _labels = {
    'first_name': 'Nombre',
    'last_name': 'Apellido',
    'email': 'Correo electrónico',
    'password': 'Contraseña',
  };
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final field in _labels.keys) field: TextEditingController(),
  };
  String? _bank;
  String? _error;
  Json? _account;
  String? _credentials;
  bool _busy = false;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String? _validate(String field, String value) {
    if (value.trim().isEmpty) return 'Campo obligatorio';
    if (field == 'email' &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      return 'Escribe un correo válido.';
    }
    if (field == 'password') {
      if (value.length < 12) return 'Usa al menos 12 caracteres.';
      if (utf8.encode(value).length > 72) return 'Usa como máximo 72 bytes.';
    }
    return null;
  }

  Future<void> _register() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await auth.request(
        'POST',
        '/auth/self-register',
        authenticated: false,
        body: {
          'tenant_slug': _bank,
          for (final field in _fields.entries)
            field.key: field.key == 'password'
                ? field.value.text
                : field.value.text.trim(),
        },
      ) as Json;
      if (!mounted) return;
      final account = result['account'] as Json;
      final user = result['user'] as Json;
      final banks = ref.read(bankDirectoryProvider).asData?.value ?? <Json>[];
      final bankName = banks
          .where((bank) => bank['slug'] == _bank)
          .map((bank) => bank['name'])
          .firstOrNull;
      final credentials =
          'Banco: ${bankName ?? _bank}\n'
          'Identificador: $_bank\n'
          'Correo: ${user['email']}\n'
          'Contraseña: ${_fields['password']!.text}\n'
          'Número de cuenta: ${account['number']}\n'
          'Moneda: ${account['currency']}';
      _fields['password']!.clear();
      setState(() {
        _account = account;
        _credentials = credentials;
      });
    } on ApiError catch (error) {
      if (mounted) {
        setState(
          () => _error = error.status == 409
              ? 'No se pudo completar el registro. Si ya te registraste en este banco, inicia sesión.'
              : error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCredentials() async {
    final credentials = _credentials;
    if (credentials == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: credentials));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credenciales y número de cuenta copiados.'),
        ),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo copiar. Vuelve a intentar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(bankDirectoryProvider);
    final account = _account;
    return Scaffold(
      appBar: AppBar(title: const Text('Registro')),
      body: SafeArea(
        child: account != null
            ? BankPage(
                title: 'Cuenta creada',
                children: [
                  Text(
                    'Tu cuenta ${account['number']} está activa en ${account['currency']}.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _copyCredentials,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar credenciales y cuenta'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.go('/login?banco=$_bank'),
                    child: const Text('Iniciar sesión'),
                  ),
                ],
              )
            : directory.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => BankPage(
                  title: 'No se pudieron cargar los bancos',
                  children: [
                    if (error is ApiError) Text(error.message),
                    TextButton(
                      onPressed: () => ref.invalidate(bankDirectoryProvider),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
                data: (banks) {
                  if (banks.isEmpty) {
                    return const BankPage(
                      title: 'Registro',
                      children: [Text('Por ahora no hay bancos disponibles.')],
                    );
                  }
                  return Form(
                    key: _form,
                    child: BankPage(
                      title: 'Abre tu cuenta',
                      form: true,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _bank,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Banco'),
                          items: [
                            for (final bank in banks)
                              DropdownMenuItem(
                                value: bank['slug'] as String,
                                child: Text(
                                  '${bank['name']} (${bank['slug']})',
                                ),
                              ),
                          ],
                          onChanged: _busy ? null : (value) => _bank = value,
                          validator: (value) =>
                              value == null ? 'Selecciona un banco.' : null,
                        ),
                        for (final field in _labels.entries)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextFormField(
                              controller: _fields[field.key],
                              enabled: !_busy,
                              obscureText: field.key == 'password',
                              keyboardType: field.key == 'email'
                                  ? TextInputType.emailAddress
                                  : null,
                              maxLength:
                                  [
                                    'first_name',
                                    'last_name',
                                  ].contains(field.key)
                                  ? 80
                                  : null,
                              decoration: InputDecoration(
                                labelText: field.value,
                                errorMaxLines: 3,
                              ),
                              validator: (value) =>
                                  _validate(field.key, value ?? ''),
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
                          onPressed: _busy ? null : _register,
                          child: Text(
                            _busy ? 'Creando cuenta…' : 'Registrarme',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

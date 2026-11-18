import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/session_provider.dart';
import '../services/banks_service.dart';

import 'package:go_router/go_router.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/themes/app_colors.dart';

class LoginScreem extends ConsumerStatefulWidget {
  const LoginScreem({super.key, this.initialBank});

  final String? initialBank;

  @override
  ConsumerState<LoginScreem> createState() => _LoginScreemState();
}

class _LoginScreemState extends ConsumerState<LoginScreem> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _customBank = TextEditingController();
  String? _bank;
  String? _error;
  bool _busy = false;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    final bank = widget.initialBank;
    if (bank != null) {
      _bank = bank;
      _customBank.text = bank;
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        final token = await const BanksService().loginPlatform(
          _email.text.trim(),
          _password.text,
        );
        if (!mounted) return;
        ref.read(platformSessionProvider.notifier).login(token);
        context.go('/operador');
        return;
      } on ApiError catch (error) {
        if (error.status != 401) rethrow;
      }
      if (_bank == null) {
        throw const ApiError(
          'Revisa tus credenciales y selecciona tu banco para ingresar.',
        );
      }
      if (_bank == '__other__' &&
          !RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$')
              .hasMatch(_customBank.text.trim().toLowerCase())) {
        throw const ApiError('Escribe un identificador de banco válido.');
      }
      await auth.login(
        tenantSlug: _bank == '__other__'
            ? _customBank.text.trim().toLowerCase()
            : _bank!,
        correo: _email.text,
        contrasena: _password.text,
      );
      if (mounted) context.go(auth.role == 'ADMIN' ? '/admin' : '/cliente');
    } on ApiError catch (error) {
      if (mounted) {
        setState(
          () => _error = error.status == 401
              ? 'Revisa el banco, el correo y la contraseña.'
              : error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _customBank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(bankDirectoryProvider).asData?.value;
    final banks = {
      ...AuthService.banks,
      for (final bank in directory ?? <Json>[])
        bank['slug'] as String: bank['name'] as String,
    };
    final selected = _bank;
    if (selected != null && selected != '__other__') {
      banks.putIfAbsent(selected, () => selected);
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset('assets/logo.png', width: 140),
                    ),
                    const SizedBox(height: 40),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: Text(
                          'ACCESO SEGURO',
                          style: TextStyle(color: naranja),
                        ),
                        backgroundColor: superficieSecundaria,
                        side: BorderSide.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bienvenido\na Moke bank.',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ingresa con tu usuario o correo y contraseña.',
                      style: TextStyle(color: textoSecundario50),
                    ),
                    const SizedBox(height: 24),
                    if (ref.watch(
                      sessionProvider.select((session) => session.expired),
                    )) ...[
                      const Text(
                        'Tu sesión venció. Vuelve a iniciar sesión.',
                        style: TextStyle(color: textoError),
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: _bank,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Banco (para clientes y administradores)',
                      ),
                      hint: const Text('Selecciona tu banco'),
                      items: [
                        for (final bank in banks.entries)
                          DropdownMenuItem(
                            value: bank.key,
                            child: Text(bank.value),
                          ),
                        const DropdownMenuItem(
                          value: '__other__',
                          child: Text('Otro banco'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _bank = value),
                    ),
                    if (_bank == '__other__') ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _customBank,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Identificador del banco',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Usuario o correo electrónico',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Escribe tu usuario o correo'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _hide,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        suffixIcon: IconButton(
                          tooltip: _hide
                              ? 'Mostrar contraseña'
                              : 'Ocultar contraseña',
                          onPressed: () => setState(() => _hide = !_hide),
                          icon: Icon(
                            _hide
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Escribe tu contraseña' : null,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: textoError)),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy ? 'Identificando acceso…' : 'Iniciar sesión',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => context.push('/registro'),
                      child: const Text('Registrarme en un banco'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

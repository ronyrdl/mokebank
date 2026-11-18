import '../shared/rate_format.dart';

import 'package:flutter/material.dart';

import 'dart:async';

import '../../services/request_id.dart';

import 'package:moke_bank/services/notification_service.dart';

import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';
import 'package:moke_bank/screems/shared/movement_details.dart';

import 'pin_dialog.dart';

import 'package:moke_bank/services/transactions_service.dart';

enum Operation {
  transfer('Transferir'),
  deposit('Depositar'),
  withdraw('Retirar');

  const Operation(this.label);
  final String label;
}

class OperationScreen extends StatefulWidget {
  const OperationScreen({
    super.key,
    required this.kind,
    required this.accounts,
    required this.onCompleted,
  });
  final Operation kind;
  final List<Json> accounts;
  final VoidCallback onCompleted;
  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends State<OperationScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _destination = TextEditingController();
  late Json _account = widget.accounts.first;
  Json? _quote;
  Json? _receipt;
  Json? _pending;
  String? _key;
  String? _correlationId;
  String? _error;
  bool _busy = false;

  bool get _transfer => widget.kind == Operation.transfer;

  Json get _input => {
    if (_transfer)
      'source_account_id': _account['id']
    else
      'account_id': _account['id'],
    if (_transfer)
      'destination_account_number': _destination.text.replaceAll(
        RegExp(r'\s'),
        '',
      ),
    'amount': _amount.text.trim().replaceAll(',', '.'),
  };

  @override
  void dispose() {
    _amount.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    final retry = _pending != null;
    if (!retry && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_transfer && _quote == null && !retry) {
        final quote = await const TransactionsService().quote(
          _input.cast<String, String>(),
        );
        if (mounted) setState(() => _quote = quote);
        return;
      }
      if (!retry && widget.kind != Operation.deposit) {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PinDialog(),
        );
        if (!mounted || accepted != true) return;
      }
      _pending ??= {..._input, if (_quote != null) 'expected_quote': _quote};
      _key ??= newRequestId();
      _correlationId ??= newRequestId();
      final result = await const TransactionsService().submit(
        widget.kind.name,
        _pending!,
        _key!,
        _correlationId!,
      );
      if (mounted) {
        setState(() => _receipt = result);
        if (result['status'] == 'COMPLETED') widget.onCompleted();
      }
      if (result['id'] case final String id
          when result['status'] == 'COMPLETED') {
        unawaited(
          const NotificationService().operationCompleted(widget.kind.name, id),
        );
      }
    } on ApiError catch (error) {
      if (error.status != 0 &&
          error.status < 500 &&
          error.status != 429 &&
          error.code != 'OPERATION_PROCESSING') {
        _pending = null;
        _key = null;
        _correlationId = null;
      }
      if (!mounted) return;
      if (error.code == 'QUOTE_CHANGED') _quote = null;
      setState(
        () => _error = _pending != null
            ? '${error.message} Reintenta para consultar la misma operación.'
            : error.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final receipt = _receipt;
    final locked = _busy || quote != null || _pending != null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            receipt != null
                ? 'Comprobante'
                : quote != null
                ? 'Revisar transferencia'
                : widget.kind.label,
          ),
        ),
        body: receipt != null
            ? BankPage(
                title: receipt['status'] == 'COMPLETED'
                    ? 'Operación completada'
                    : 'Resultado de la operación',
                children: [
                  if (receipt['status'] == 'COMPLETED')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        for (final field in movementFields(receipt).entries)
                          ListTile(
                            title: Text(field.key),
                            subtitle: Text('${field.value ?? '—'}'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Volver al inicio'),
                  ),
                ],
              )
            : Form(
                key: _form,
                child: BankPage(
                  children: [
                    SectionLabel(
                      widget.kind == Operation.deposit
                          ? 'Cuenta destino'
                          : 'Cuenta de origen',
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Json>(
                      initialValue: _account,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: widget.kind == Operation.deposit
                            ? 'Cuenta destino'
                            : 'Cuenta de origen',
                      ),
                      items: [
                        for (final account in widget.accounts)
                          DropdownMenuItem(
                            value: account,
                            child: Text(accountLabel(account)),
                          ),
                      ],
                      onChanged: locked
                          ? null
                          : (account) => setState(() => _account = account!),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Saldo disponible: ${_account['balance']} ${_account['currency']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_transfer) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _destination,
                        readOnly: locked,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número de cuenta destino',
                        ),
                        validator: (value) =>
                            RegExp(r'^\d{6,32}$')
                                .hasMatch(value!.replaceAll(RegExp(r'\s'), ''))
                            ? null
                            : 'Escribe un número de cuenta válido',
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amount,
                      readOnly: locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Monto',
                        suffixText: '${_account['currency']}',
                      ),
                      validator: (value) {
                        final amount = value!.trim().replaceAll(',', '.');
                        return RegExp(r'^(0|[1-9]\d{0,17})(\.\d{1,2})?$')
                                    .hasMatch(amount) &&
                                RegExp(r'[1-9]').hasMatch(amount)
                            ? null
                            : 'Escribe un monto positivo con hasta 2 decimales';
                      },
                    ),
                    if (quote != null) ...[
                      ListTile(
                        title: const Text('El destinatario recibe'),
                        subtitle: Text(
                          '${quote['converted_amount']} ${quote['destination_currency']}',
                        ),
                      ),
                      ListTile(
                        title: const Text('Monto enviado'),
                        subtitle: Text(
                          '${quote['original_amount']} ${quote['source_currency']}',
                        ),
                      ),
                      ListTile(
                        title: const Text('Comisión'),
                        subtitle: Text(
                          '${quote['fee']} ${quote['source_currency']}',
                        ),
                      ),
                      if (quote['source_currency'] !=
                          quote['destination_currency'])
                        ListTile(
                          title: const Text('Tasa de cambio'),
                          subtitle: Text(
                            '1 ${quote['source_currency']} = ${formatExchangeRate(quote['exchange_rate'])} ${quote['destination_currency']}',
                          ),
                        ),
                      ListTile(
                        title: const Text('Total a debitar'),
                        subtitle: Text(
                          '${quote['total_debit']} ${quote['source_currency']}',
                        ),
                      ),
                      if (_pending == null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _quote = null),
                          child: const Text('Editar'),
                        ),
                    ],
                    const SizedBox(height: 16),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _continue,
                      child: Text(
                        _busy
                            ? 'Procesando…'
                            : _pending != null
                            ? 'Reintentar'
                            : _transfer && quote == null
                            ? 'Revisar transferencia'
                            : 'Confirmar',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

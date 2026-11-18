import 'package:flutter/material.dart';

import '../../services/accounts_service.dart';
import '../../services/auth_service.dart';
import '../../services/transactions_service.dart';
import '../../themes/app_colors.dart';
import '../shared/bank_widgets.dart';
import '../shared/movement_details.dart';
import 'operation_screen.dart';

class ClientHome extends StatelessWidget {
  const ClientHome({super.key, required this.showMovements});
  final VoidCallback showMovements;

  @override
  Widget build(BuildContext context) => BankLoader(
    refreshInterval: const Duration(seconds: 10),
    load: () => (
      const AccountsService().list(),
      const TransactionsService().list(filters: {'limit': '3'}),
    ).wait,
    builder: (data, reload) {
      final active = data.$1
          .where((account) => account['status'] == 'ACTIVE')
          .toList();
      final movements = (data.$2['items'] as List).cast<Json>();
      return BankPage(
        title: auth.bankName,
        eyebrow: Text(
          'Hola, ${auth.user!['first_name']}',
          style: const TextStyle(color: textoSecundario50),
        ),
        children: [
          if (data.$1.isEmpty)
            const Text('Aún no tienes cuentas en este banco.'),
          if (data.$1.isNotEmpty)
            SizedBox(
              height: 142,
              child: LayoutBuilder(
                builder: (context, layout) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: data.$1.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => SizedBox(
                    width: data.$1.length == 1
                        ? layout.maxWidth
                        : (layout.maxWidth * .82).clamp(210, 320).toDouble(),
                    child: _AccountCard(data.$1[index]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Acciones rápidas'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final operation in Operation.values) ...[
                if (operation != Operation.values.first)
                  const SizedBox(width: 8),
                Expanded(
                  child: _QuickAction(
                    operation: operation,
                    onPressed: active.isEmpty
                        ? null
                        : () => _openOperation(context, operation, reload),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: SectionLabel('Movimientos recientes')),
              TextButton(
                onPressed: showMovements,
                child: const Text('Ver todos'),
              ),
            ],
          ),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no hay movimientos.',
                style: TextStyle(color: textoSecundario50),
              ),
            ),
          for (final row in movements) movementTile(context, row),
        ],
      );
    },
  );
  Future<void> _openOperation(
    BuildContext context,
    Operation operation,
    VoidCallback reload,
  ) async {
    var completed = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: BankLoader(
              load: const AccountsService().list,
              builder: (accounts, _) {
                final active = accounts
                    .where((account) => account['status'] == 'ACTIVE')
                    .toList();
                if (active.isEmpty) {
                  return BankPage(
                    title: operation.label,
                    children: [
                      const Text('No hay cuentas activas para esta operación.'),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Volver al inicio'),
                      ),
                    ],
                  );
                }
                return OperationScreen(
                  kind: operation,
                  accounts: active,
                  onCompleted: () {
                    completed = true;
                    reload();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    if (!completed) reload();
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard(this.account);
  final Json account;

  @override
  Widget build(BuildContext context) {
    final status = account['status'];
    final (label, color) = switch (status) {
      'ACTIVE' => ('Activa', confirmacion),
      'BLOCKED' => ('Bloqueada', textoError),
      _ => ('Inactiva', textoSecundario50),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tarjetas,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borde10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Saldo disponible'),
            const Spacer(),
            Text(
              '${account['balance']} ${account['currency']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                StatusLabel(label, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    accountLabel(account),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textoSecundario50,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.operation, required this.onPressed});
  final Operation operation;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      backgroundColor: tarjetas,
      foregroundColor: textoPrincipal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(switch (operation) {
          Operation.transfer => Icons.swap_horiz,
          Operation.deposit => Icons.south_west,
          Operation.withdraw => Icons.north_east,
        }, color: onPressed == null ? textoSecundario30 : naranja),
        const SizedBox(height: 4),
        Text(
          operation.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/screems/shared/bank_widgets.dart';
import 'package:moke_bank/screems/shared/profile_page.dart';

import 'admin_client_screen.dart';
import 'admin_accounts_screen.dart';
import 'admin_movements_screen.dart';
import 'admin_settings_screen.dart';

import 'package:moke_bank/services/accounts_service.dart';
import 'package:moke_bank/services/clients_service.dart';
import 'package:moke_bank/services/banks_service.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, this.selectedIndex = 0});
  final int selectedIndex;
  static const paths = [
    '/admin',
    '/admin/clientes',
    '/admin/cuentas',
    '/admin/movimientos',
    '/admin/configuracion',
    '/admin/perfil',
  ];
  static const labels = [
    'Inicio',
    'Clientes',
    'Cuentas',
    'Movimientos',
    'Configuración',
    'Perfil',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.people_outline,
    Icons.account_balance_wallet_outlined,
    Icons.receipt_long_outlined,
    Icons.settings_outlined,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    void navigate(int index) => context.go(paths[index]);
    final page = switch (selectedIndex) {
      1 => const AdminClientScreen(),
      2 => const AdminAccountsScreen(),
      3 => const AdminMovementsScreen(),
      4 => const AdminSettingsScreen(),
      5 => profilePage(context),
      _ => BankLoader(
        load: () => (
          const BanksService().config(),
          const ClientsService().list(),
          const AccountsService().list(),
        ).wait,
        builder: (data, _) => BankPage(
          title: data.$1['name'] as String,
          eyebrow: Text('Buenos días, ${auth.user!['first_name']}'),
          children: [
            Row(
              children: [
                for (final (label, count, index) in [
                  (
                    'Clientes',
                    data.$2.where((user) => user['role'] == 'CLIENT').length,
                    1,
                  ),
                  ('Cuentas', data.$3.length, 2),
                ]) ...[
                  if (index == 2) const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => navigate(index),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionLabel(label),
                              const SizedBox(height: 8),
                              Text(
                                '$count',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            const SectionLabel('Gestión del banco'),
            const SizedBox(height: 10),
            for (final (index, description) in [
              (1, 'Crear y administrar'),
              (2, 'Estados y saldos'),
              (3, 'Operaciones y estadísticas'),
              (4, 'Comisiones, tasas y webhooks'),
            ])
              Card(
                child: ListTile(
                  leading: Icon(
                    icons[index],
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(labels[index]),
                  subtitle: Text(description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => navigate(index),
                ),
              ),
          ],
        ),
      ),
    };
    final mobileIndex = selectedIndex == 5
        ? 3
        : selectedIndex > 2
        ? 0
        : selectedIndex;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/favicon.png', width: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Moke · ${auth.bankName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: navigate,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(labels[i]),
                        ),
                    ],
                  ),
                  Expanded(child: page),
                ],
              )
            : page,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: mobileIndex,
              onDestinationSelected: (index) =>
                  navigate(index == 3 ? 5 : index),
              destinations: [
                for (var i = 0; i < 3; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Perfil',
                ),
              ],
            ),
    );
  }
}

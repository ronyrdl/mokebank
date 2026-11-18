import 'package:flutter/material.dart';
import 'package:moke_bank/services/auth_service.dart';

import 'bank_widgets.dart';

Widget profilePage(BuildContext context) => BankPage(
  title: 'Perfil',
  children: [
    Center(
      child: CircleAvatar(
        radius: 30,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        foregroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.person_outline, size: 30),
      ),
    ),
    const SizedBox(height: 12),
    Text(
      fullName(auth.user!),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    Text(
      '${auth.user!['email']}',
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: 26),
    const SectionLabel('Banco activo'),
    const SizedBox(height: 8),
    Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_outlined),
        title: Text(auth.bankName),
        subtitle: Text('${auth.bank}'),
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: () async {
        try {
          await auth.logout();
        } on ApiError {
          // The local session is cleared even when the server is unreachable.
        }
      },
      child: const Text('Cerrar sesión'),
    ),
  ],
);

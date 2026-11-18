import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/profile_page.dart';
import '../shared/movements_screen.dart';
import 'client_home.dart';

class ClientScreen extends StatelessWidget {
  const ClientScreen({super.key, required this.index});
  final int index;
  static const paths = ['/cliente', '/cliente/movimientos', '/cliente/perfil'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Image.asset('assets/favicon.png', width: 28),
          const SizedBox(width: 8),
          const Text('Moke'),
        ],
      ),
    ),
    body: SafeArea(
      child: switch (index) {
        1 => const Movements(),
        2 => profilePage(context),
        _ => ClientHome(showMovements: () => context.go(paths[1])),
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (index) => context.go(paths[index]),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Movimientos',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Perfil',
        ),
      ],
    ),
  );
}

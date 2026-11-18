import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screems/admin/admin_screen.dart';
import '../screems/client/client_screen.dart';
import '../screems/login_screem.dart';
import '../screems/operator/operator_screen.dart';
import '../screems/welcome.dart';
import '../providers/session_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    redirect: (context, state) {
      final path = state.uri.path;
      final role = ref.read(sessionProvider).role;
      final home = switch (role) {
        'ADMIN' => '/admin',
        'CLIENT' => '/cliente',
        _ => null,
      };
      if ((path == '/' || path == '/login') && home != null) return home;
      if (AdminScreen.paths.contains(path) && role != 'ADMIN' ||
          ClientScreen.paths.contains(path) && role != 'CLIENT') {
        return home ?? '/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Welcome()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreem()),
      for (final (index, path) in AdminScreen.paths.indexed)
        GoRoute(
          path: path,
          builder: (context, state) => AdminScreen(selectedIndex: index),
        ),
      for (final (index, path) in ClientScreen.paths.indexed)
        GoRoute(
          path: path,
          builder: (context, state) => ClientScreen(index: index),
        ),
      if (kIsWeb)
        GoRoute(
          path: '/operador',
          builder: (context, state) => const OperatorScreen(),
        ),
    ],
  );
  ref.listen(sessionProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

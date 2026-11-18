import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screems/admin/admin_screen.dart';
import '../screems/client/client_screen.dart';
import '../screems/login_screem.dart';
import '../screems/operator/operator_screen.dart';
import '../screems/register_screen.dart';
import '../screems/welcome.dart';
import '../providers/session_provider.dart';
import '../services/banks_service.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    redirect: (context, state) {
      final path = state.uri.path;
      final platform = ref.read(platformSessionProvider) != null;
      if (platform) return path == '/operador' ? null : '/operador';
      final role = ref.read(sessionProvider).role;
      if (path == '/operador') return '/login';
      final home = switch (role) {
        'ADMIN' => '/admin',
        'CLIENT' => '/cliente',
        _ => null,
      };
      if (['/', '/login', '/registro', '/operador'].contains(path) &&
          home != null) {
        return home;
      }
      if (AdminScreen.paths.contains(path) && role != 'ADMIN' ||
          ClientScreen.paths.contains(path) && role != 'CLIENT') {
        return home ?? '/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Welcome()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreem(initialBank: state.uri.queryParameters['banco']),
      ),
      GoRoute(
        path: '/registro',
        builder: (context, state) => const RegisterScreen(),
      ),
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
      GoRoute(
        path: '/operador',
        builder: (context, state) => const OperatorScreen(),
      ),
    ],
  );
  ref.listen(sessionProvider, (_, _) => router.refresh());
  ref.listen(platformSessionProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

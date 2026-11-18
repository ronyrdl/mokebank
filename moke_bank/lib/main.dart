import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moke_bank/router/app_router.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/themes/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await auth.restore();
  runApp(const ProviderScope(child: MokeApp()));
}

class MokeApp extends ConsumerWidget {
  const MokeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'Moke Bank',
    theme: buildAppTheme(),
    routerConfig: ref.watch(appRouterProvider),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moke_bank/services/auth_service.dart';

class BankPage extends StatelessWidget {
  const BankPage({super.key, this.title, this.eyebrow, required this.children});
  final String? title;
  final Widget? eyebrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (eyebrow != null) ...[eyebrow!, const SizedBox(height: 4)],
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
          ],
          ...children,
        ],
      ),
    ),
  );
}

class BankLoader<T> extends ConsumerStatefulWidget {
  const BankLoader({
    super.key,
    required this.load,
    required this.builder,
    this.refreshInterval,
  });
  final Duration? refreshInterval;
  final Future<T> Function() load;
  final Widget Function(T data, VoidCallback reload) builder;

  @override
  ConsumerState<BankLoader<T>> createState() => _BankLoaderState<T>();
}

class _BankLoaderState<T> extends ConsumerState<BankLoader<T>> {
  late final _dataProvider = FutureProvider.autoDispose<T>(
    (_) => widget.load(),
    retry: (_, _) => null,
  );

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final interval = widget.refreshInterval;
    if (interval == null) return;
    _refreshTimer = Timer.periodic(interval, (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          ModalRoute.of(context)?.isCurrent == false ||
          ref.read(_dataProvider).isLoading) {
        return;
      }
      _reload();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) ref.invalidate(_dataProvider);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(_dataProvider)
      .when(
        skipLoadingOnRefresh: widget.refreshInterval != null,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => BankPage(
          title: 'No se pudieron cargar los datos',
          children: [
            Text('$error'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('Reintentar')),
          ],
        ),
        data: (data) => widget.builder(data, _reload),
      );
}

String accountLabel(Json account) {
  final number = '${account['number']}';
  return '•••• ${number.length > 4 ? number.substring(number.length - 4) : number} · ${account['currency']}';
}

String fullName(Json user) => '${user['first_name']} ${user['last_name']}';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class StatusLabel extends StatelessWidget {
  const StatusLabel(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

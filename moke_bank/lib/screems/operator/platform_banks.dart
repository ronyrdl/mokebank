import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/banks_service.dart';
import '../shared/bank_widgets.dart';

class PlatformBanks extends ConsumerStatefulWidget {
  const PlatformBanks({super.key});

  @override
  ConsumerState<PlatformBanks> createState() => _PlatformBanksState();
}

class _PlatformBanksState extends ConsumerState<PlatformBanks> {
  bool _busy = false;

  Future<void> _changeStatus(Json bank) async {
    final active = bank['active'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${active ? 'Desactivar' : 'Activar'} ${bank['name']}'),
        content: Text(
          active
              ? 'Los usuarios de este banco perderán el acceso y se bloquearán nuevas operaciones. Podrás reactivarlo desde este panel.'
              : 'Los usuarios podrán volver a ingresar y operar en este banco.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(active ? 'Desactivar' : 'Activar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      final token = ref.read(platformSessionProvider);
      if (token == null) return;
      await const BanksService().setStatus(
        token,
        bank['id'] as String,
        !active,
      );
      if (!mounted) return;
      ref.invalidate(platformBanksProvider);
      ref.invalidate(bankDirectoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active ? 'Banco desactivado.' : 'Banco activado.'),
        ),
      );
    } on ApiError catch (error) {
      if (!mounted) return;
      if (error.status == 403 || error.status == 401) {
        ref.read(platformSessionProvider.notifier).logout();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(platformBanksProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => BankPage(
          title: 'Bancos',
          children: [
            Text(error.toString()),
            TextButton(
              onPressed: () {
                if (error is ApiError && [401, 403].contains(error.status)) {
                  ref.read(platformSessionProvider.notifier).logout();
                } else {
                  ref.invalidate(platformBanksProvider);
                }
              },
              child: Text(
                error is ApiError && [401, 403].contains(error.status)
                    ? 'Volver a iniciar sesión'
                    : 'Reintentar',
              ),
            ),
          ],
        ),
        data: (banks) => BankPage(
          title: 'Bancos',
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Actualizar bancos',
                onPressed: _busy
                    ? null
                    : () => ref.invalidate(platformBanksProvider),
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (banks.isEmpty) const Text('Todavía no hay bancos registrados.'),
            for (final bank in banks)
              Card(
                child: ListTile(
                  title: Text('${bank['name']}'),
                  subtitle: Text(
                    '${bank['slug']} · ${bank['active'] == true ? 'Activo' : 'Inactivo'}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _changeStatus(bank),
                    child: Text(
                      bank['active'] == true ? 'Desactivar' : 'Activar',
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

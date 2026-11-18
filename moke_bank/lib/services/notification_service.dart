import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationService {
  const NotificationService();

  static const _channel = MethodChannel('moke_bank/notifications');

  Future<void> operationCompleted(String operation, String reference) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final title = switch (operation) {
      'deposit' => 'Depósito completado',
      'withdraw' => 'Retiro completado',
      'transfer' => 'Transferencia completada',
      _ => 'Operación completada',
    };

    try {
      await _channel.invokeMethod<void>('operationCompleted', {
        'title': title,
        'reference': reference,
      });
    } on PlatformException catch (error) {
      debugPrint('No se pudo mostrar el aviso de Moke: ${error.code}');
    } on MissingPluginException {
      // The native channel is available after rebuilding the Android app.
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moke_bank/services/biometric_service.dart';

class PinDialog extends StatefulWidget {
  const PinDialog({super.key});
  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  String _pin = '';
  bool _invalid = false;
  bool _checkingBiometrics = false;
  String? _biometricError;
  static const _biometrics = BiometricService();

  Future<void> _authenticate() async {
    setState(() {
      _checkingBiometrics = true;
      _biometricError = null;
    });
    try {
      final accepted = await _biometrics.authenticate();
      if (mounted && accepted) Navigator.pop(context, true);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _biometricError =
              error.message ?? 'No se pudo verificar la biometría.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _biometricError = 'Reinicia la app para usar la biometría.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingBiometrics = false);
    }
  }

  static const _demoPin = String.fromEnvironment(
    'BANKOS_DEMO_PIN',
    defaultValue: '2580',
  );

  void _digit(int digit) {
    setState(() {
      _invalid = false;
      _pin += '$digit';
    });
    if (_pin.length == 4) {
      if (_pin == _demoPin) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _invalid = true;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_checkingBiometrics,
    child: AlertDialog(
      title: const Text('Confirmación segura'),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_biometrics.supported) ...[
                FilledButton.icon(
                  onPressed: _checkingBiometrics ? null : _authenticate,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(
                    _checkingBiometrics ? 'Verificando…' : 'Usar huella',
                  ),
                ),
                if (_biometricError != null) Text(_biometricError!),
                const Divider(height: 24),
              ],
              const Text('PIN de demostración'),
              Text(
                List.generate(
                  4,
                  (i) => i < _pin.length ? '●' : '○',
                ).join('   '),
              ),
              if (_invalid) const Text('PIN incorrecto. Inténtalo de nuevo.'),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final digit in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
                    SizedBox(
                      width: 65,
                      child: OutlinedButton(
                        onPressed: _checkingBiometrics
                            ? null
                            : () => _digit(digit),
                        child: Text('$digit'),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Borrar dígito',
                    onPressed: _checkingBiometrics || _pin.isEmpty
                        ? null
                        : () => setState(
                            () => _pin = _pin.substring(0, _pin.length - 1),
                          ),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checkingBiometrics
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancelar operación'),
        ),
      ],
    ),
  );
}

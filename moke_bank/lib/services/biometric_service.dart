import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BiometricService {
  const BiometricService();

  static const _channel = MethodChannel('moke_bank/biometrics');

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> authenticate() async =>
      supported && (await _channel.invokeMethod<bool>('authenticate') ?? false);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  const SessionStorage();

  static const _key = 'bankos.session.v1';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> read() async {
    if (!_supported) return null;
    try {
      return await _storage.read(key: _key);
    } on PlatformException {
      debugPrint('BankOS: no se pudo restaurar la sesión segura.');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> save(String? value) async {
    if (!_supported) return;
    try {
      if (value == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: value);
      }
    } on PlatformException {
      debugPrint('BankOS: no se pudo actualizar la sesión segura.');
    } on MissingPluginException {
      // The native storage is only available on supported builds.
    }
  }
}

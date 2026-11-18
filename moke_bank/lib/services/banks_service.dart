import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

final bankDirectoryProvider = FutureProvider.autoDispose(
  (ref) => const BanksService().directory(),
);

class BanksService {
  const BanksService();

  Future<List<Json>> directory() =>
      auth.page('/tenants/directory', authenticated: false);

  Future<String> loginPlatform(String username, String password) async {
    final data = await auth.request(
      'POST',
      '/tenants/platform-login',
      authenticated: false,
      body: {'username': username, 'password': password},
    ) as Json;
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiError(
        'La API devolvió una sesión de plataforma inválida.',
      );
    }
    return token;
  }

  Future<Json> config() => auth.get('/tenants/config');

  Future<void> updateConfig(Json settings) async {
    await auth.request('PATCH', '/tenants/config', body: settings);
  }

  Future<Json> create({
    required String platformToken,
    required Json bank,
  }) async => await auth.request(
    'POST',
    '/tenants',
    authenticated: false,
    headers: {'Authorization': 'Bearer $platformToken'},
    body: bank,
  ) as Json;
}

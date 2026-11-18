import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

final bankDirectoryProvider = FutureProvider.autoDispose(
  (ref) => const BanksService().directory(),
);

final platformSessionProvider = NotifierProvider<PlatformSession, String?>(
  PlatformSession.new,
);

class PlatformSession extends Notifier<String?> {
  @override
  String? build() => null;

  void login(String token) => state = token;
  void logout() => state = null;
}

final platformBanksProvider = FutureProvider.autoDispose((ref) {
  final token = ref.watch(platformSessionProvider);
  if (token == null) return Future.value(<Json>[]);
  return const BanksService().listPlatform(token);
});

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

  Future<List<Json>> listPlatform(String token) async {
    final banks = <Json>[];
    for (var page = 1; ; page++) {
      final data = await auth.request(
        'GET',
        '/tenants',
        authenticated: false,
        headers: {'Authorization': 'Bearer $token'},
        query: {'page': '$page', 'limit': '100'},
      ) as Json;
      banks.addAll((data['items'] as List).cast<Json>());
      if (data['has_more'] != true) return banks;
    }
  }

  Future<void> setStatus(String token, String id, bool active) async {
    await auth.request(
      'PATCH',
      '/tenants/$id/status',
      authenticated: false,
      headers: {'Authorization': 'Bearer $token'},
      body: {'active': active},
    );
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

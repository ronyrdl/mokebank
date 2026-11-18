import 'auth_service.dart';

class BanksService {
  const BanksService();

  Future<Json> config() => auth.get('/tenants/config');

  Future<void> updateConfig(Json settings) async {
    await auth.request('PATCH', '/tenants/config', body: settings);
  }

  Future<Json> create({
    required String platformKey,
    required Json bank,
  }) async => await auth.request(
    'POST',
    '/tenants',
    authenticated: false,
    headers: {'X-Platform-Key': platformKey},
    body: bank,
  ) as Json;
}

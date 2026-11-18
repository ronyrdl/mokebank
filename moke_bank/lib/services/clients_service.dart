import 'auth_service.dart';

class ClientsService {
  const ClientsService();

  Future<List<Json>> list() => auth.page('/users');

  Future<void> create(Json client) async {
    await auth.request('POST', '/users', body: client);
  }

  Future<void> setActive(String id, bool active) async {
    await auth.request('PATCH', '/users/$id/status', body: {'active': active});
  }
}

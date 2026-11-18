import 'auth_service.dart';

class AccountsService {
  const AccountsService();

  Future<List<Json>> list() => auth.page('/accounts');

  Future<Json> create({
    required String owner,
    required String currency,
  }) async => await auth.request(
    'POST',
    '/accounts',
    body: {'owner_id': owner, 'currency': currency},
  ) as Json;

  Future<void> setStatus(String id, String status) async {
    await auth.request(
      'PATCH',
      '/accounts/$id/status',
      body: {'status': status},
    );
  }
}

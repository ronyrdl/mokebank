import 'auth_service.dart';

class TransactionsService {
  const TransactionsService();

  Future<Json> list({Map<String, String>? filters}) =>
      auth.get('/transactions', query: filters);

  Future<List<Json>> stats() async =>
      (await auth.request('GET', '/transactions/stats') as List).cast<Json>();

  Future<Json> quote(Map<String, String> input) =>
      auth.get('/transactions/quote', query: input);

  Future<Json> submit(
    String operation,
    Json input,
    String key,
    String correlationId,
  ) async => await auth.request(
    'POST',
    '/transactions/$operation',
    body: input,
    headers: {'Idempotency-Key': key, 'X-Correlation-ID': correlationId},
  ) as Json;
}

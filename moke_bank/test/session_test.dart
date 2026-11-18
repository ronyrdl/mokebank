import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moke_bank/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'login uses the selected bank and clears the session on expiration',
    () async {
      final service = AuthService();
      addTearDown(service.dispose);
      var calls = 0;

      await http.runWithClient(
        () async {
          await service.login(
            tenantSlug: 'demo-b',
            correo: ' usuario@example.com ',
            contrasena: 'demo-password',
          );
          expect(service.bank, 'demo-b');
          expect(service.role, 'CLIENT');

          final restored = AuthService();
          addTearDown(restored.dispose);
          await restored.restore();
          expect(restored.bank, 'demo-b');
          expect(restored.role, 'CLIENT');

          await expectLater(
            restored.get('/accounts'),
            throwsA(isA<ApiError>()),
          );
          expect(restored.expired, isTrue);
          expect(restored.role, isNull);
          expect(restored.bank, isNull);
          final afterRejection = AuthService();
          addTearDown(afterRejection.dispose);
          await afterRejection.restore();
          expect(afterRejection.role, isNull);
          expect(calls, 2);
        },
        () => MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/auth/login')) {
            expect(jsonDecode(request.body), {
              'tenant_slug': 'demo-b',
              'email': 'usuario@example.com',
              'password': 'demo-password',
            });
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'user': {'role': 'CLIENT'},
                  'access_token': 'test-token',
                  'expires_in': 60,
                },
              }),
              200,
            );
          }
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response('{"success":false,"code":"UNAUTHORIZED"}', 401);
        }),
      );
    },
  );
}

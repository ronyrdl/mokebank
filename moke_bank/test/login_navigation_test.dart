import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moke_bank/main.dart';
import 'package:moke_bank/services/auth_service.dart';
import 'package:moke_bank/themes/app_colors.dart';

void main() {
  testWidgets('successful client login leaves the login screen', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var balance = '0.00';
    (String?, String?, String)? firstAttempt;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const ProviderScope(child: MokeApp()));
        await tester.tap(find.text('Comenzar'));
        await tester.pumpAndSettle();
        final bank = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(bank);
        await tester.tap(bank);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Banco Demo A').last);
        await tester.pumpAndSettle();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'client@example.com');
        await tester.enterText(fields.at(1), 'test-password');
        final submit = find.text('Iniciar sesión');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(find.text('Hola, Cliente'), findsOneWidget);
        expect(find.text('Identificando acceso…'), findsNothing);

        final transfer = tester.getCenter(find.text('Transferir'));
        expect(transfer.dy, tester.getCenter(find.text('Retirar')).dy);
        final nav = tester.element(find.byType(NavigationBar));
        expect(
          NavigationBarTheme.of(nav).iconTheme
              ?.resolve({WidgetState.selected})
              ?.color,
          naranja,
        );

        await tester.tap(find.text('Depositar'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).last, '10');
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        final back = find.text('Volver al inicio');
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('10.00 USD'), findsOneWidget);
        expect(find.text('0.00 USD'), findsNothing);
        for (final action in ['Transferir', 'Retirar', 'Depositar']) {
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(find.text('Saldo disponible: 10.00 USD'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }

        await auth.logout();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/deposit')) {
          final attempt = (
            request.headers['idempotency-key'],
            request.headers['x-correlation-id'],
            request.body,
          );
          expect(attempt.$1, isNotEmpty);
          expect(attempt.$2, isNotEmpty);
          if (firstAttempt == null) {
            firstAttempt = attempt;
            return http.Response('{"success":false}', 503);
          }
          expect(attempt, firstAttempt);
          balance = '10.00';
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'deposit-1',
                'status': 'COMPLETED',
                'original_amount': '10.00',
              },
            }),
            201,
          );
        }
        final data = request.url.path.endsWith('/login')
            ? {
                'user': {'role': 'CLIENT', 'first_name': 'Cliente'},
                'access_token': 'test-token',
                'expires_in': 60,
              }
            : {
                'items': [
                  if (request.url.path.endsWith('/accounts'))
                    {
                      'id': 'test-account',
                      'number': '900000101',
                      'currency': 'USD',
                      'balance': balance,
                      'status': 'ACTIVE',
                    },
                ],
                'has_more': false,
              };
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      }),
    );
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zywny_auth/zywny_auth.dart';

import 'support/fake_browser.dart';

void main() {
  group('LoopbackOAuthFlow (D01)', () {
    test('troca o código do navegador por um token de identidade', () async {
      late http.Request tokenRequest;
      final idToken = fakeIdToken(email: 'aluno@zywny.app', name: 'Aluno');
      final client = MockClient((request) async {
        if (request.url.toString().contains('oauth2.googleapis.com')) {
          tokenRequest = request;
          return http.Response(
            jsonEncode({
              'id_token': idToken,
              'access_token': 'access-de-teste',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final flow = LoopbackOAuthFlow(
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: client,
        browserLauncher: fakeBrowser(code: 'codigo-123'),
      );

      final result = await flow.signIn();

      expect(result.idToken, idToken);
      expect(result.email, 'aluno@zywny.app');
      expect(result.displayName, 'Aluno');
      // O endereço de volta é o do servidor local (o Firebase exige o mesmo).
      expect(result.requestUri, startsWith('http://127.0.0.1:'));

      // A troca leva o código e o verificador do PKCE.
      expect(tokenRequest.bodyFields['code'], 'codigo-123');
      expect(tokenRequest.bodyFields['grant_type'], 'authorization_code');
      expect(tokenRequest.bodyFields['code_verifier'], isNotEmpty);
      expect(
        tokenRequest.bodyFields['client_id'],
        'cliente.apps.googleusercontent.com',
      );
    });

    test('o endereço de autorização leva o pedido do PKCE', () async {
      Uri? authorization;
      final client = MockClient((request) async {
        if (request.url.toString().contains('oauth2.googleapis.com')) {
          return http.Response(jsonEncode({'id_token': fakeIdToken()}), 200);
        }
        return http.Response('{}', 404);
      });

      final flow = LoopbackOAuthFlow(
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: client,
        browserLauncher: (url) async {
          authorization = url;
          return false;
        },
      );

      await expectLater(flow.signIn(), throwsA(isA<AuthException>()));

      expect(authorization, isNotNull);
      expect(authorization!.queryParameters['code_challenge_method'], 'S256');
      expect(authorization!.queryParameters['code_challenge'], isNotEmpty);
      expect(authorization!.queryParameters['state'], isNotEmpty);
      expect(
        authorization!.queryParameters['redirect_uri'],
        startsWith('http://127.0.0.1:'),
      );
    });

    test('o navegador volta com um estado diferente: o app recusa', () async {
      final flow = LoopbackOAuthFlow(
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: MockClient((_) async => http.Response('{}', 500)),
        browserLauncher: fakeBrowserWithWrongState(),
      );

      await expectLater(
        flow.signIn(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'mensagem',
            contains('estado diferente'),
          ),
        ),
      );
    });

    test('o navegador não abriu: o app avisa', () async {
      final flow = LoopbackOAuthFlow(
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: MockClient((_) async => http.Response('{}', 500)),
        browserLauncher: fakeBrowser(fail: true),
      );

      await expectLater(
        flow.signIn(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'mensagem',
            contains('navegador'),
          ),
        ),
      );
    });

    test('o provedor recusa a troca do código: o app avisa', () async {
      final flow = LoopbackOAuthFlow(
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'código inválido',
            }),
            400,
          ),
        ),
        browserLauncher: fakeBrowser(),
      );

      await expectLater(
        flow.signIn(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'mensagem',
            contains('código inválido'),
          ),
        ),
      );
    });
  });
}

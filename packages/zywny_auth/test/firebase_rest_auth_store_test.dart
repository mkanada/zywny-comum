import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_auth/zywny_auth.dart';

import 'support/fake_browser.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('FirebaseRestAuthStore (D01)', () {
    late DateTime now;
    late List<http.Request> requests;

    /// O servidor de mentira: responde à troca do código (Google), ao login
    /// (Firebase), à renovação e à exclusão da conta.
    http.Client fakeServer() => MockClient((request) async {
      requests.add(request);
      final url = request.url.toString();
      if (url.contains('oauth2.googleapis.com')) {
        return http.Response(
          jsonEncode({
            'id_token': fakeIdToken(),
            'access_token': 'access-de-teste',
            'expires_in': 3600,
          }),
          200,
        );
      }
      if (url.contains('accounts:signInWithIdp')) {
        return http.Response(
          jsonEncode({
            'idToken': 'token-do-firebase',
            'refreshToken': 'refresh-do-firebase',
            'expiresIn': '3600',
            'localId': 'uid-123',
            'email': 'aluno@zywny.app',
            'displayName': 'Aluno de Teste',
          }),
          200,
        );
      }
      if (url.contains('securetoken.googleapis.com')) {
        return http.Response(
          jsonEncode({
            'id_token': 'token-renovado',
            'refresh_token': 'refresh-renovado',
            'expires_in': '3600',
          }),
          200,
        );
      }
      if (url.contains('accounts:delete')) {
        return http.Response('{}', 200);
      }
      if (url.contains('accounts:signOut')) {
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    FirebaseRestAuthStore makeStore(
      http.Client client, {
      DateTime Function()? clock,
    }) {
      return FirebaseRestAuthStore(
        apiKey: 'chave-de-teste',
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: client,
        prefs: SharedPreferencesAsync(),
        clock: clock ?? () => now,
        flow: LoopbackOAuthFlow(
          clientId: 'cliente.apps.googleusercontent.com',
          httpClient: client,
          browserLauncher: fakeBrowser(),
        ),
      );
    }

    setUp(() {
      now = DateTime.utc(2026, 10, 19, 12);
      requests = [];
    });

    test('entra com o Google e fica com a sessão guardada', () async {
      final store = makeStore(fakeServer());
      await store.signInWithProvider(SocialProvider.google);

      expect(store.value.status, AuthStatus.authenticated);
      expect(store.currentUser?.uid, 'uid-123');
      expect(store.currentUser?.email, 'aluno@zywny.app');
      expect(store.currentUser?.providerId, 'google.com');
      expect(store.currentUser?.idToken, 'token-do-firebase');
      expect(store.currentUser?.lastServerCheckAt, now);

      // A sessão fica no aparelho, para o app abrir já conectado.
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString(SessionStorage.uidKey), 'uid-123');
      expect(
        await prefs.getString(SessionStorage.idTokenKey),
        'token-do-firebase',
      );
      expect(
        await prefs.getInt(SessionFreshness.lastVerifiedKey),
        now.millisecondsSinceEpoch,
      );
    });

    test('restaura a sessão guardada em outro app aberto', () async {
      final client = fakeServer();
      await makeStore(client).signInWithProvider(SocialProvider.google);

      // O app fecha e abre de novo: a sessão volta do aparelho.
      final outro = makeStore(client);
      await outro.restore();
      expect(outro.value.status, AuthStatus.authenticated);
      expect(outro.currentUser?.uid, 'uid-123');
    });

    test('renova o token e a marca do servidor visto', () async {
      final client = fakeServer();
      final store = makeStore(client);
      await store.signInWithProvider(SocialProvider.google);

      now = now.add(const Duration(minutes: 30));
      await store.refreshSession();

      expect(store.currentUser?.idToken, 'token-renovado');
      expect(store.currentUser?.refreshToken, 'refresh-renovado');
      expect(store.currentUser?.lastServerCheckAt, now);
      expect(store.value.status, AuthStatus.authenticated);
    });

    test('passados 7 dias sem rede, a sessão guardada não vale', () async {
      final client = fakeServer();
      await makeStore(client).signInWithProvider(SocialProvider.google);

      now = now.add(const Duration(days: 7, minutes: 1));
      final store = makeStore(client);
      await store.restore();

      expect(store.value.status, AuthStatus.offlineExpired);
      expect(store.value.errorMessage, contains('7 dias'));
      // A pessoa continua no estado: é o app que pede a conexão.
      expect(store.currentUser?.uid, 'uid-123');
    });

    test('no sétimo dia ainda vale (7 dias é o limite)', () async {
      final client = fakeServer();
      await makeStore(client).signInWithProvider(SocialProvider.google);

      now = now.add(const Duration(days: 7));
      final store = makeStore(client);
      await store.restore();

      expect(store.value.status, AuthStatus.authenticated);
    });

    test('relógio do aparelho atrasado: a sessão não vale', () async {
      final client = fakeServer();
      await makeStore(client).signInWithProvider(SocialProvider.google);

      now = now.subtract(const Duration(days: 1));
      final store = makeStore(client);
      await store.restore();

      expect(store.value.status, AuthStatus.offlineExpired);
      expect(store.value.errorMessage, contains('relógio'));
    });

    test(
      'sem rede, renovar a sessão deixa o aviso e não derruba o acesso',
      () async {
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.toString().contains('oauth2.googleapis.com')) {
            return http.Response(jsonEncode({'id_token': fakeIdToken()}), 200);
          }
          if (request.url.toString().contains('accounts:signInWithIdp')) {
            return http.Response(
              jsonEncode({
                'idToken': 'token-do-firebase',
                'refreshToken': 'refresh-do-firebase',
                'expiresIn': '3600',
                'localId': 'uid-123',
              }),
              200,
            );
          }
          // O securetoken não responde: a rede caiu.
          throw http.ClientException('sem rede');
        });
        final store = makeStore(client);
        await store.signInWithProvider(SocialProvider.google);

        await store.refreshSession();

        expect(store.value.status, AuthStatus.authenticated);
        expect(store.value.errorMessage, isNotNull);
        expect(store.currentUser?.uid, 'uid-123');
      },
    );

    test('sem rede há mais de 7 dias, renovar leva a pedir conexão', () async {
      final client = MockClient((request) async {
        if (request.url.toString().contains('oauth2.googleapis.com')) {
          return http.Response(jsonEncode({'id_token': fakeIdToken()}), 200);
        }
        if (request.url.toString().contains('accounts:signInWithIdp')) {
          return http.Response(
            jsonEncode({
              'idToken': 'token-do-firebase',
              'refreshToken': 'refresh-do-firebase',
              'expiresIn': '3600',
              'localId': 'uid-123',
            }),
            200,
          );
        }
        throw http.ClientException('sem rede');
      });
      final store = makeStore(client);
      await store.signInWithProvider(SocialProvider.google);

      now = now.add(const Duration(days: 8));
      await store.refreshSession();

      expect(store.value.status, AuthStatus.offlineExpired);
    });

    test('sair da conta apaga a sessão guardada', () async {
      final client = fakeServer();
      final store = makeStore(client);
      await store.signInWithProvider(SocialProvider.google);

      await store.signOut();

      expect(store.value.status, AuthStatus.unauthenticated);
      expect(store.currentUser, isNull);
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString(SessionStorage.uidKey), isNull);
      expect(await prefs.getString(SessionStorage.idTokenKey), isNull);
      expect(
        requests.any((r) => r.url.toString().contains('accounts:signOut')),
        isTrue,
      );
    });

    test('apagar a conta chama o Firebase e limpa os dados locais', () async {
      final client = fakeServer();
      final store = makeStore(client);
      await store.signInWithProvider(SocialProvider.google);

      await store.deleteAccount();

      expect(store.value.status, AuthStatus.unauthenticated);
      final delete = requests.firstWhere(
        (r) => r.url.toString().contains('accounts:delete'),
      );
      expect(jsonDecode(delete.body)['idToken'], 'token-do-firebase');
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString(SessionStorage.uidKey), isNull);
      expect(await prefs.getString(SessionStorage.nicknameKey), isNull);
    });

    test('troca o apelido e guarda no aparelho', () async {
      final store = makeStore(fakeServer());
      await store.signInWithProvider(SocialProvider.google);

      await store.updateNickname('  Tucano  ');

      expect(store.currentUser?.nickname, 'Tucano');
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString(SessionStorage.nicknameKey), 'Tucano');
    });

    test('no computador, por enquanto, só o Google', () async {
      final store = makeStore(fakeServer());
      await store.signInWithProvider(SocialProvider.apple);

      expect(store.value.status, AuthStatus.unauthenticated);
      expect(store.value.errorMessage, contains('Google'));
    });

    test('o navegador não abriu: a tela mostra o erro', () async {
      final client = fakeServer();
      final store = FirebaseRestAuthStore(
        apiKey: 'chave-de-teste',
        clientId: 'cliente.apps.googleusercontent.com',
        httpClient: client,
        prefs: SharedPreferencesAsync(),
        clock: () => now,
        flow: LoopbackOAuthFlow(
          clientId: 'cliente.apps.googleusercontent.com',
          httpClient: client,
          browserLauncher: fakeBrowser(fail: true),
        ),
      );

      await store.signInWithProvider(SocialProvider.google);

      expect(store.value.status, AuthStatus.unauthenticated);
      expect(store.value.errorMessage, contains('navegador'));
    });
  });
}

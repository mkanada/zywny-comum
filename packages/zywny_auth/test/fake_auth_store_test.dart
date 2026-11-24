import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';

void main() {
  group('FakeAuthStore (D01)', () {
    test('loggedIn: o app passa, com alguém conectado', () {
      final store = FakeAuthStore.loggedIn();
      expect(store.state.status, AuthStatus.authenticated);
      expect(store.state.isAuthenticated, isTrue);
      expect(store.currentUser?.uid, 'fake-uid');
    });

    test('loggedOut: o app fica na tela de entrada', () {
      final store = FakeAuthStore.loggedOut();
      expect(store.state.status, AuthStatus.unauthenticated);
      expect(store.currentUser, isNull);
    });

    test('offlineExpired: o app pede conexão', () {
      final store = FakeAuthStore.offlineExpired();
      expect(store.state.status, AuthStatus.offlineExpired);
      expect(store.state.errorMessage, contains('7 dias'));
    });

    test('initializing: o app mostra o carregando', () {
      final store = FakeAuthStore.initializing();
      expect(store.state.status, AuthStatus.initializing);
    });

    test('entrar, sair e apagar a conta', () async {
      final store = FakeAuthStore.loggedOut();

      await store.signInWithProvider(SocialProvider.google);
      expect(store.signInCalls, 1);
      expect(store.lastProvider, SocialProvider.google);
      expect(store.state.status, AuthStatus.authenticated);

      await store.signOut();
      expect(store.signOutCalls, 1);
      expect(store.state.status, AuthStatus.unauthenticated);

      await store.deleteAccount();
      expect(store.deleteAccountCalls, 1);
      expect(store.state.status, AuthStatus.unauthenticated);
    });

    test('renovar a sessão', () async {
      final store = FakeAuthStore.loggedIn();
      await store.refreshSession();
      expect(store.refreshCalls, 1);
      expect(store.state.status, AuthStatus.authenticated);
    });

    test('trocar o apelido', () async {
      final store = FakeAuthStore.loggedIn();
      await store.updateNickname('  Tucano  ');
      expect(store.nicknameCalls, 1);
      expect(store.currentUser?.nickname, 'Tucano');
    });
  });

  group('FakeAuthStore como Cubit (BL09)', () {
    blocTest<FakeAuthStore, AuthState>(
      'entrar emite a sessão conectada com o provedor escolhido',
      build: () => FakeAuthStore.loggedOut(),
      act: (store) => store.signInWithProvider(SocialProvider.apple),
      expect: () => [
        isA<AuthState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having(
              (s) => s.user?.providerId,
              'providerId',
              SocialProvider.apple.id,
            ),
      ],
      verify: (store) {
        expect(store.signInCalls, 1);
        expect(store.state.isAuthenticated, isTrue);
      },
    );

    blocTest<FakeAuthStore, AuthState>(
      'sair emite o estado sem ninguém conectado',
      build: () => FakeAuthStore.loggedIn(),
      act: (store) => store.signOut(),
      expect: () => [const AuthState.unauthenticated()],
      verify: (store) => expect(store.signOutCalls, 1),
    );

    blocTest<FakeAuthStore, AuthState>(
      'um erro (apelido sem ninguém conectado) não emite estado novo',
      build: () => FakeAuthStore.loggedOut(),
      act: (store) => expectLater(
        store.updateNickname('Ana'),
        throwsA(isA<AuthException>()),
      ),
      expect: () => <AuthState>[],
      verify: (store) {
        expect(store.nicknameCalls, 1);
        expect(store.state.status, AuthStatus.unauthenticated);
      },
    );

    blocTest<FakeAuthStore, AuthState>(
      'o mesmo estado de novo não avisa de novo',
      build: () => FakeAuthStore.loggedOut(),
      act: (store) => store.mudar(const AuthState.unauthenticated()),
      expect: () => <AuthState>[],
    );
  });
}

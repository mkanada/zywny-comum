import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';

void main() {
  group('FakeAuthStore (D01)', () {
    test('loggedIn: o app passa, com alguém conectado', () {
      final store = FakeAuthStore.loggedIn();
      expect(store.value.status, AuthStatus.authenticated);
      expect(store.value.isAuthenticated, isTrue);
      expect(store.currentUser?.uid, 'fake-uid');
    });

    test('loggedOut: o app fica na tela de entrada', () {
      final store = FakeAuthStore.loggedOut();
      expect(store.value.status, AuthStatus.unauthenticated);
      expect(store.currentUser, isNull);
    });

    test('offlineExpired: o app pede conexão', () {
      final store = FakeAuthStore.offlineExpired();
      expect(store.value.status, AuthStatus.offlineExpired);
      expect(store.value.errorMessage, contains('7 dias'));
    });

    test('initializing: o app mostra o carregando', () {
      final store = FakeAuthStore.initializing();
      expect(store.value.status, AuthStatus.initializing);
    });

    test('entrar, sair e apagar a conta', () async {
      final store = FakeAuthStore.loggedOut();

      await store.signInWithProvider(SocialProvider.google);
      expect(store.signInCalls, 1);
      expect(store.lastProvider, SocialProvider.google);
      expect(store.value.status, AuthStatus.authenticated);

      await store.signOut();
      expect(store.signOutCalls, 1);
      expect(store.value.status, AuthStatus.unauthenticated);

      await store.deleteAccount();
      expect(store.deleteAccountCalls, 1);
      expect(store.value.status, AuthStatus.unauthenticated);
    });

    test('renovar a sessão', () async {
      final store = FakeAuthStore.loggedIn();
      await store.refreshSession();
      expect(store.refreshCalls, 1);
      expect(store.value.status, AuthStatus.authenticated);
    });

    test('trocar o apelido', () async {
      final store = FakeAuthStore.loggedIn();
      await store.updateNickname('  Tucano  ');
      expect(store.nicknameCalls, 1);
      expect(store.currentUser?.nickname, 'Tucano');
    });
  });
}

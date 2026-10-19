import 'auth_state.dart';
import 'auth_store.dart';
import 'auth_user.dart';

/// Um [AuthStore] de mentira, para os testes dos dois apps (D01): nenhum
/// teste tem rede nem Firebase configurado, e o `FakeAuthStore` deixa
/// injetar um usuário já conectado.
class FakeAuthStore extends AuthStoreBase implements AuthStore {
  FakeAuthStore([AuthState? initial]) {
    setState(initial ?? const AuthState.unauthenticated());
  }

  /// Já conectado: o [AuthGate] (D02) deixa o app passar.
  factory FakeAuthStore.loggedIn({
    String uid = 'fake-uid',
    String? nickname,
    String? email = 'aluno@zywny.app',
    String providerId = 'google.com',
  }) {
    return FakeAuthStore(
      AuthState.authenticated(
        AuthUser(
          uid: uid,
          providerId: providerId,
          idToken: 'fake-id-token',
          email: email,
          displayName: nickname ?? 'Aluno de Teste',
          refreshToken: 'fake-refresh-token',
          lastServerCheckAt: DateTime.now(),
          nickname: nickname,
        ),
      ),
    );
  }

  /// Sem ninguém: o app fica na tela de entrada.
  factory FakeAuthStore.loggedOut() =>
      FakeAuthStore(const AuthState.unauthenticated());

  /// A sessão guardada passou dos 7 dias: o app pede conexão.
  factory FakeAuthStore.offlineExpired({
    String uid = 'fake-uid',
    String? nickname,
  }) {
    return FakeAuthStore(
      AuthState.offlineExpired(
        user: AuthUser(
          uid: uid,
          providerId: 'google.com',
          idToken: 'fake-id-token',
          refreshToken: 'fake-refresh-token',
          lastServerCheckAt: DateTime.now(),
          nickname: nickname,
        ),
        errorMessage:
            'Faz mais de 7 dias sem conexão. Conecte-se à internet para '
            'renovar seu acesso.',
      ),
    );
  }

  /// Ainda decidindo: o app mostra o carregando.
  factory FakeAuthStore.initializing() =>
      FakeAuthStore(const AuthState.initializing());

  /// Quantas vezes cada método foi chamado (para o teste conferir).
  int signInCalls = 0;
  int refreshCalls = 0;
  int signOutCalls = 0;
  int deleteAccountCalls = 0;
  int nicknameCalls = 0;
  SocialProvider? lastProvider;
  String? lastNickname;

  @override
  Future<void> restore() async {}

  @override
  Future<void> signInWithProvider(SocialProvider provider) async {
    signInCalls++;
    lastProvider = provider;
    setState(
      AuthState.authenticated(
        AuthUser(
          uid: 'fake-uid',
          providerId: provider.id,
          idToken: 'fake-id-token',
          email: 'aluno@zywny.app',
          displayName: 'Aluno de Teste',
          refreshToken: 'fake-refresh-token',
          lastServerCheckAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Future<void> refreshSession() async {
    refreshCalls++;
    final user = currentUser;
    if (user == null) return;
    setState(
      AuthState.authenticated(user.copyWith(lastServerCheckAt: DateTime.now())),
    );
  }

  @override
  Future<void> updateNickname(String nickname) async {
    nicknameCalls++;
    lastNickname = nickname;
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        'Não há ninguém conectado para ter um apelido.',
      );
    }
    final trimmed = nickname.trim();
    setState(
      AuthState.authenticated(
        user.copyWith(nickname: trimmed.isEmpty ? null : trimmed),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    setState(const AuthState.unauthenticated());
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    setState(const AuthState.unauthenticated());
  }
}

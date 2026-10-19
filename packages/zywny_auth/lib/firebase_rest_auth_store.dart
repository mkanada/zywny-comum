import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';
import 'auth_store.dart';
import 'auth_user.dart';
import 'loopback_oauth.dart';
import 'session_freshness.dart';
import 'session_storage.dart';

/// O login no desktop (Linux e Windows), onde o SDK do Firebase não tem
/// plugin nativo: o navegador do sistema faz a autenticação (loopback OAuth)
/// e a troca dos tokens é feita na API REST oficial do Firebase Identity
/// Toolkit (D01).
///
/// A regra dos 7 dias sem rede (D-NEG-OFFLINE) é a mesma dos outros
/// caminhos: a sessão guardada vale até uma semana depois da última vez que o
/// servidor respondeu.
class FirebaseRestAuthStore extends AuthStoreBase implements AuthStore {
  FirebaseRestAuthStore({
    required this.apiKey,
    required this.clientId,
    this.clientSecret,
    http.Client? httpClient,
    SharedPreferencesAsync? prefs,
    this.flow,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _storage = SessionStorage(prefs: prefs),
       _clock = clock ?? DateTime.now;

  /// A chave da Web do projeto no Firebase (a mesma que vai no
  /// `firebase_options.dart`).
  final String apiKey;

  /// O OAuth Client ID do login pelo navegador do sistema.
  final String clientId;

  /// O segredo do cliente (só no tipo "Web application").
  final String? clientSecret;

  final http.Client _http;
  final SessionStorage _storage;
  final DateTime Function() _clock;

  /// O login pelo navegador, quando o app já tem um pronto (nos testes).
  final LoopbackOAuthFlow? flow;

  LoopbackOAuthFlow get _oauth =>
      flow ??
      LoopbackOAuthFlow(
        clientId: clientId,
        clientSecret: clientSecret,
        httpClient: _http,
      );

  static const String _identityToolkit =
      'https://identitytoolkit.googleapis.com';
  static const String _secureToken = 'https://securetoken.googleapis.com';

  @override
  Future<void> restore() async {
    final user = await _storage.read();
    if (user == null) {
      setState(const AuthState.unauthenticated());
      return;
    }
    final now = _clock();
    if (!SessionFreshness.isFresh(user.lastServerCheckAt, now)) {
      setState(
        AuthState.offlineExpired(
          user: user,
          errorMessage: SessionFreshness.messageFor(
            lastVerified: user.lastServerCheckAt,
            now: now,
          ),
        ),
      );
      return;
    }
    setState(AuthState.authenticated(user));
  }

  @override
  Future<void> signInWithProvider(SocialProvider provider) async {
    try {
      if (provider != SocialProvider.google) {
        throw const AuthException(
          'No computador, por enquanto, só o login com Google funciona.',
        );
      }
      final result = await _oauth.signIn();
      final user = await _signInWithIdp(result, provider);
      await _storage.write(user);
      setState(AuthState.authenticated(user));
    } on AuthException catch (e) {
      setState(AuthState.unauthenticated(errorMessage: e.message));
    } on Object catch (e) {
      setState(
        AuthState.unauthenticated(errorMessage: 'Não consegui entrar: $e'),
      );
    }
  }

  @override
  Future<void> refreshSession() async {
    final user = currentUser;
    final refreshToken = user?.refreshToken;
    if (user == null || refreshToken == null) {
      setState(
        const AuthState.unauthenticated(
          errorMessage: 'Não há sessão para renovar.',
        ),
      );
      return;
    }
    try {
      final response = await _http.post(
        Uri.parse('$_secureToken/v1/token?key=$apiKey'),
        headers: const {'content-type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      );
      if (response.statusCode != 200) {
        throw AuthException(
          'O servidor recusou a renovação: ${_errorFrom(response)}',
        );
      }
      final body = _decodeObject(response.body);
      final idToken = body['id_token'] as String?;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('O servidor não devolveu o token novo.');
      }
      final now = _clock();
      final updated = user.copyWith(
        idToken: idToken,
        refreshToken: body['refresh_token'] as String? ?? refreshToken,
        idTokenExpiresAt: now.add(
          Duration(seconds: _asInt(body['expires_in']) ?? 3600),
        ),
        lastServerCheckAt: now,
      );
      await _storage.write(updated);
      setState(AuthState.authenticated(updated));
    } on Object catch (e) {
      // A rede falhou: a sessão guardada continua valendo enquanto estiver
      // fresca (D-NEG-OFFLINE).
      final now = _clock();
      if (!SessionFreshness.isFresh(user.lastServerCheckAt, now)) {
        setState(
          AuthState.offlineExpired(
            user: user,
            errorMessage: SessionFreshness.messageFor(
              lastVerified: user.lastServerCheckAt,
              now: now,
            ),
          ),
        );
      } else {
        setState(
          AuthState.authenticated(
            user,
            errorMessage: 'Não consegui falar com o servidor agora: $e',
          ),
        );
      }
    }
  }

  @override
  Future<void> updateNickname(String nickname) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        'Não há ninguém conectado para ter um apelido.',
      );
    }
    final trimmed = nickname.trim();
    final updated = user.copyWith(nickname: trimmed.isEmpty ? null : trimmed);
    await _storage.write(updated);
    setState(AuthState.authenticated(updated));
  }

  @override
  Future<void> signOut() async {
    final refreshToken = currentUser?.refreshToken;
    if (refreshToken != null) {
      // Revoga o token no servidor — melhor esforço: sem rede, sai do mesmo
      // jeito e a sessão local some.
      try {
        await _http.post(
          Uri.parse('$_identityToolkit/v1/accounts:signOut?key=$apiKey'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        );
      } on Object {
        // Sem rede: a sessão local é apagada assim mesmo.
      }
    }
    await _storage.clear();
    setState(const AuthState.unauthenticated());
  }

  @override
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user != null) {
      final response = await _http.post(
        Uri.parse('$_identityToolkit/v1/accounts:delete?key=$apiKey'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': user.idToken}),
      );
      if (response.statusCode != 200) {
        throw AuthException(
          'Não consegui apagar a conta: ${_errorFrom(response)}',
        );
      }
    }
    await _storage.clear();
    setState(const AuthState.unauthenticated());
  }

  /// Troca o token do provedor por uma sessão do Firebase.
  Future<AuthUser> _signInWithIdp(
    OAuthResult result,
    SocialProvider provider,
  ) async {
    final response = await _http.post(
      Uri.parse('$_identityToolkit/v1/accounts:signInWithIdp?key=$apiKey'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'postBody':
            'id_token=${Uri.encodeComponent(result.idToken)}&providerId=${provider.id}',
        'requestUri': result.requestUri,
        'returnIdpCredential': true,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode != 200) {
      throw AuthException(
        'O Firebase recusou o login: ${_errorFrom(response)}',
      );
    }
    final body = _decodeObject(response.body);
    final uid = body['localId'] as String?;
    final idToken = body['idToken'] as String?;
    if (uid == null || uid.isEmpty || idToken == null || idToken.isEmpty) {
      throw const AuthException('O Firebase não devolveu a sessão.');
    }
    final now = _clock();
    // O apelido é do Zywny: ele só continua se for a mesma pessoa.
    final previous = await _storage.read();
    final nickname = previous?.uid == uid ? previous?.nickname : null;
    return AuthUser(
      uid: uid,
      providerId: provider.id,
      idToken: idToken,
      email: body['email'] as String? ?? result.email,
      displayName: body['displayName'] as String? ?? result.displayName,
      photoUrl: body['photoUrl'] as String?,
      refreshToken: body['refreshToken'] as String?,
      idTokenExpiresAt: now.add(
        Duration(seconds: _asInt(body['expiresIn']) ?? 3600),
      ),
      lastServerCheckAt: now,
      nickname: nickname,
    );
  }

  static Map<String, dynamic> _decodeObject(String text) {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static int? _asInt(Object? value) => switch (value) {
    int v => v,
    String v => int.tryParse(v),
    _ => null,
  };

  static String _errorFrom(http.Response response) {
    try {
      final body = _decodeObject(response.body);
      final message = body['error']['message'] ?? body['error'];
      if (message is String && message.isNotEmpty) return message;
    } on Object {
      // A resposta não era um JSON: cai no código abaixo.
    }
    return 'o servidor respondeu ${response.statusCode}';
  }
}

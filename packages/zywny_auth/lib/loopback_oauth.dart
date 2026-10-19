import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth_state.dart';
// O servidor local de volta do navegador só existe onde há `dart:io`. Na Web
// quem entra é o popup do Firebase (D01).
import 'src/loopback_server_stub.dart'
    if (dart.library.io) 'src/loopback_server_io.dart';

/// Abre o navegador do sistema no endereço de autorização. Os testes trocam
/// essa função por uma que finge o navegador.
typedef BrowserLauncher = Future<bool> Function(Uri url);

/// O que o navegador devolveu depois do login.
@immutable
class OAuthResult {
  const OAuthResult({
    required this.idToken,
    required this.requestUri,
    this.accessToken,
    this.email,
    this.displayName,
  });

  /// O token de identidade do provedor (o `id_token` do Google).
  final String idToken;

  /// O endereço de volta que o Firebase exige no `requestUri`.
  final String requestUri;

  final String? accessToken;
  final String? email;
  final String? displayName;
}

/// O login social no navegador do sistema, com o servidor local de volta
/// (loopback OAuth) e a troca do código por um token de identidade.
///
/// É o caminho do Linux e do Windows, onde o SDK do Firebase não tem plugin
/// nativo (D00, D01). No Android e na Web quem entra é o SDK
/// ([FirebaseSdkAuthStore]).
class LoopbackOAuthFlow {
  LoopbackOAuthFlow({
    required this.clientId,
    this.clientSecret,
    http.Client? httpClient,
    BrowserLauncher? browserLauncher,
    this.authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth',
    this.tokenEndpoint = 'https://oauth2.googleapis.com/token',
    this.scopes = const ['openid', 'email', 'profile'],
    this.port = 0,
    this.timeout = const Duration(minutes: 5),
  }) : _http = httpClient ?? http.Client(),
       _browser = browserLauncher;

  /// O OAuth Client ID do projeto (o mesmo do console do Google).
  final String clientId;

  /// O segredo do cliente. Só o cliente do tipo "Web application" tem; o do
  /// tipo "Desktop" usa PKCE e não tem segredo.
  final String? clientSecret;

  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String> scopes;

  /// A porta do servidor local (0 = uma livre). Com o cliente do tipo
  /// "Desktop" o Google aceita qualquer porta do `127.0.0.1`; com o do tipo
  /// "Web application" a porta precisa estar registrada no console.
  final int port;

  /// Quanto esperar o navegador voltar.
  final Duration timeout;

  final http.Client _http;
  final BrowserLauncher? _browser;

  /// Faz o login: abre o navegador, espera a volta com o código e troca o
  /// código por um token de identidade.
  Future<OAuthResult> signIn() async {
    final server = await LoopbackServer.bind(port: port);
    try {
      final verifier = _randomToken();
      final state = _randomToken();
      final redirectUri = server.redirectUri;
      final url = Uri.parse(authorizationEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri.toString(),
          'response_type': 'code',
          'scope': scopes.join(' '),
          'state': state,
          'code_challenge': _codeChallenge(verifier),
          'code_challenge_method': 'S256',
          'prompt': 'select_account',
        },
      );
      // O servidor já escuta antes de o navegador abrir: a resposta pode
      // chegar a qualquer momento.
      final code = server.waitForCode(expectedState: state, timeout: timeout);
      // A promessa ganha um ouvinte desde já: se o navegador responder antes
      // de a espera começar, o erro não vaza como "não tratado".
      unawaited(code.then((_) {}, onError: (Object _) {}));
      final launched = await (_browser ?? _openInSystemBrowser)(url);
      if (!launched) {
        throw const AuthException(
          'Não consegui abrir o navegador para o login.',
        );
      }
      return await _exchange(await code, verifier, redirectUri);
    } finally {
      server.cancel();
      await server.close();
    }
  }

  /// Troca o código do navegador por um token de identidade.
  Future<OAuthResult> _exchange(
    String code,
    String verifier,
    Uri redirectUri,
  ) async {
    final response = await _http.post(
      Uri.parse(tokenEndpoint),
      headers: const {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
        'client_secret': ?clientSecret,
      },
    );
    if (response.statusCode != 200) {
      throw AuthException(
        'O provedor recusou o login: ${_errorFrom(response)}',
      );
    }
    final body = _decodeObject(response.body);
    final idToken = body['id_token'] as String?;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'O provedor não devolveu o token de identidade.',
      );
    }
    final claims = _claimsFromIdToken(idToken);
    return OAuthResult(
      idToken: idToken,
      requestUri: redirectUri.toString(),
      accessToken: body['access_token'] as String?,
      email: claims['email'] as String?,
      displayName: claims['name'] as String?,
    );
  }

  /// Abre o navegador do sistema (o `url_launcher`).
  static Future<bool> _openInSystemBrowser(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  /// O que o token de identidade diz sobre a pessoa (o JWT tem o e-mail e o
  /// nome dentro).
  static Map<String, dynamic> _claimsFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length < 2) return const {};
    try {
      final payload = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on Object {
      return const {};
    }
  }

  static Map<String, dynamic> _decodeObject(String text) {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static String _errorFrom(http.Response response) {
    try {
      final body = _decodeObject(response.body);
      final message = body['error_description'] ?? body['error'];
      if (message is String && message.isNotEmpty) return message;
    } on Object {
      // A resposta não era um JSON: cai no código abaixo.
    }
    return 'o servidor respondeu ${response.statusCode}';
  }

  /// Um texto aleatório para o `state` e para o verificador do PKCE.
  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// O desafio do PKCE (SHA-256 do verificador, em base64url).
  static String _codeChallenge(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');
}

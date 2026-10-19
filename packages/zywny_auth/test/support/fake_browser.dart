import 'dart:convert';
import 'dart:io';

import 'package:zywny_auth/loopback_oauth.dart';

/// Um navegador de mentira: ele volta para o servidor local com o código,
/// como o navegador de verdade faria depois do login (D01).
///
/// Devolve `false` (o navegador não abriu) quando [fail] é `true`.
BrowserLauncher fakeBrowser({
  String code = 'codigo-de-teste',
  bool fail = false,
}) {
  return (url) async {
    if (fail) return false;
    final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
    final state = url.queryParameters['state']!;
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        redirect.replace(queryParameters: {'code': code, 'state': state}),
      );
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    return true;
  };
}

/// Um navegador de mentira que volta com um `state` diferente do pedido: o
/// app tem de recusar (D01).
BrowserLauncher fakeBrowserWithWrongState() {
  return (url) async {
    final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        redirect.replace(
          queryParameters: {'code': 'codigo-de-teste', 'state': 'outro-estado'},
        ),
      );
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    return true;
  };
}

/// Um `id_token` de mentira, no formato JWT (o app lê o e-mail e o nome de
/// dentro dele).
String fakeIdToken({
  String email = 'aluno@zywny.app',
  String name = 'Aluno de Teste',
  int expiresAt = 1893456000,
}) {
  String segment(Map<String, Object?> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');

  return '${segment({'alg': 'none', 'typ': 'JWT'})}.'
      '${segment({'email': email, 'name': name, 'exp': expiresAt})}.'
      'assinatura';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth_state.dart';

/// O servidor local que recebe a volta do navegador depois do login
/// (loopback OAuth). Só existe onde há `dart:io` — na Web quem entra é o
/// popup do Firebase (D01).
class LoopbackServer {
  LoopbackServer._(this._server);

  /// Sobe o servidor em `127.0.0.1` (porta 0 = escolher uma livre).
  static Future<LoopbackServer> bind({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return LoopbackServer._(server);
  }

  final HttpServer _server;
  Completer<String>? _pending;
  Timer? _timer;

  /// O endereço de volta do navegador. O Firebase exige que este endereço
  /// seja exatamente o mesmo na troca do token (o `requestUri`).
  Uri get redirectUri =>
      Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  /// Espera o navegador voltar com o código do login.
  ///
  /// O servidor já começa a escutar aqui: o navegador pode chegar antes de
  /// a promise ser esperada.
  Future<String> waitForCode({
    required String expectedState,
    required Duration timeout,
  }) {
    final completer = Completer<String>();
    _pending = completer;
    _timer = Timer(
      timeout,
      () => _fail(
        completer,
        const AuthException('O login demorou demais: o navegador não voltou.'),
      ),
    );
    _server.listen((request) async {
      final params = request.uri.queryParameters;
      final error = params['error'];
      if (error != null) {
        await _respond(request, 'O login falhou: $error');
        _fail(completer, AuthException('O provedor recusou o login ($error).'));
        return;
      }
      final state = params['state'];
      if (state != expectedState) {
        await _respond(request, 'Pedido não reconhecido.');
        _fail(
          completer,
          const AuthException(
            'A resposta do navegador não bate com o pedido (estado diferente).',
          ),
        );
        return;
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        await _respond(request, 'Pedido sem código.');
        _fail(
          completer,
          const AuthException('O navegador voltou sem o código de login.'),
        );
        return;
      }
      await _respond(request, 'Login feito.');
      if (!completer.isCompleted) completer.complete(code);
    });
    return completer.future;
  }

  /// Desiste do pedido (o navegador não abriu, por exemplo).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const AuthException('Login cancelado.'));
    }
  }

  /// Fecha o servidor.
  Future<void> close() {
    _timer?.cancel();
    _timer = null;
    return _server.close(force: true);
  }

  static void _fail(Completer<String> completer, Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  static Future<void> _respond(HttpRequest request, String message) async {
    final body =
        '<!doctype html><html lang="pt-BR"><meta charset="utf-8">'
        '<title>Zywny</title>'
        '<body style="font-family:sans-serif;text-align:center;padding:3rem">'
        '<h1>${htmlEscape.convert(message)}</h1>'
        '<p>Você pode fechar esta janela.</p></body></html>';
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(body);
    await request.response.close();
  }
}

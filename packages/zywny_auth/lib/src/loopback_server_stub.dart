import '../auth_state.dart';

/// Na Web não há servidor local: quem entra é o popup do Firebase (D01).
/// Este arquivo existe para o pacote compilar na Web (D01, D02).
class LoopbackServer {
  LoopbackServer._();

  /// Na Web não há `127.0.0.1` para o navegador voltar: o login é o popup do
  /// Firebase.
  static Future<LoopbackServer> bind({int port = 0}) async {
    throw const AuthException(
      'O login pelo navegador do sistema não funciona na Web: lá quem entra é '
      'o popup do Firebase.',
    );
  }

  Uri get redirectUri => throw UnsupportedError(
    'O login pelo navegador do sistema não funciona na Web.',
  );

  Future<String> waitForCode({
    required String expectedState,
    required Duration timeout,
  }) => throw UnsupportedError(
    'O login pelo navegador do sistema não funciona na Web.',
  );

  /// Na Web não há pedido pendente para cancelar.
  void cancel() {}

  Future<void> close() async {}
}

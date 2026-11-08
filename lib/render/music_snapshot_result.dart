/// O retrato do Verovio de uma partitura para quem a mede (T18, LP01): um texto
/// JSON `{"bridge": "...", "attributes": {"id": {"n": "1"}}}`, o que o
/// `SnapshotMusicVerovio.fromJson` do `zywny-aprendizado` lê.
///
/// Fica num arquivo sem imports de propósito: a Web importa este tipo, e o
/// `verovio_render.dart` (que traz `dart:io` e `dart:isolate`) não pode entrar
/// na compilação da Web.
class MusicSnapshotResult {
  const MusicSnapshotResult(this.json);

  /// O JSON do retrato, pronto para ser gravado ou passado de um isolate ao outro.
  final String json;
}

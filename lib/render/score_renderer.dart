import 'dart:typed_data';

import 'package:score_bridge/score_bridge.dart';

export 'page_size.dart';

import 'score_renderer_web.dart'
    if (dart.library.io) 'score_renderer_native.dart'
    as impl;

/// Tudo de que uma renderização precisa. A partitura chega como **bytes**
/// (MusicXML, MEI ou `.mxl`), não como caminho: na Web não há disco, e o
/// lado nativo é que grava o arquivo temporário que o Verovio exige.
class ScoreRenderRequest {
  const ScoreRenderRequest({
    required this.source,
    required this.fileName,
    required this.pageWidth,
    required this.pageHeight,
    this.options = const {},
  });

  final Uint8List source;

  /// Só para mensagens e para o nome do arquivo temporário.
  final String fileName;

  /// Tamanho do papel em décimos de milímetro — ver `verovio_render.dart`.
  final int pageWidth;
  final int pageHeight;

  /// As demais opções do Verovio (`layout_options.dart`).
  final Map<String, Object> options;
}

class RenderedScore {
  const RenderedScore(this.document, {this.debugCopyPath});

  final VsbDocument document;

  /// Modo `--debug` (só nativo): onde o `.vsb` foi guardado.
  final String? debugCopyPath;
}

/// Gera o [VsbDocument] de uma partitura. Duas implementações, escolhidas
/// por import condicional: nativa (FFI para `libverovio`, num isolate) e Web
/// (Verovio em wasm, num Web Worker — W01/W02).
abstract class ScoreRenderer {
  Future<RenderedScore> render(ScoreRenderRequest request);
}

ScoreRenderer createScoreRenderer() => impl.createScoreRenderer();

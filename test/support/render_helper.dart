import 'dart:io';
import 'dart:typed_data';

import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/render/score_renderer.dart';
import 'package:zywny/verovio_render.dart';

const _bridge = '/home/mauricio/rust_projects/verovio_flutter_bridge';
const kLibverovioPath = '$_bridge/verovio/bindings/dart/libverovio.so';
const kVerovioDataPath = '$_bridge/verovio/data';

/// A `libverovio.so` do bridge e os dados existem? Sem eles, os testes que
/// renderizam de verdade são pulados (como o `vsb_render_test.dart`).
bool get verovioAvailable =>
    File(kLibverovioPath).existsSync() &&
    Directory(kVerovioDataPath).existsSync();

/// Renderiza [bytes] pelo mesmo caminho do app nativo (arquivo temporário
/// com [fileName], `renderScoreToVsb`) e devolve o documento.
Future<VsbDocument> renderBytes(
  Uint8List bytes,
  String fileName, {
  int pageWidth = 1250,
  int pageHeight = 456,
  Map<String, Object> options = const {},
}) async {
  final tmp = await Directory.systemTemp.createTemp('zywny_i02');
  try {
    final input = File('${tmp.path}/$fileName')..writeAsBytesSync(bytes);
    return await renderScoreToVsb(
      VsbRenderRequest(
        inputPath: input.path,
        outputPath: '${tmp.path}/score.vsb',
        libraryPath: File(kLibverovioPath).absolute.path,
        resourcePath: Directory(kVerovioDataPath).absolute.path,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        options: options,
      ),
    );
  } finally {
    await tmp.delete(recursive: true);
  }
}

/// O `ScoreRenderer` dos testes: o mesmo ciclo do app nativo, mas com a
/// `libverovio.so` e os dados do bridge direto (o `path_provider` do app não
/// existe em `flutter test`).
class LibverovioRenderer implements ScoreRenderer {
  /// Quantas partituras já renderizou (para testes de "uma por rodada").
  int renders = 0;

  @override
  Future<RenderedScore> render(ScoreRenderRequest request) async {
    renders++;
    final document = await renderBytes(
      request.source,
      request.fileName,
      pageWidth: request.pageWidth,
      pageHeight: request.pageHeight,
      options: request.options,
    );
    return RenderedScore(document);
  }
}

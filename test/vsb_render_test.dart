// Integração ponta a ponta do caminho novo: MEI -> libverovio (FFI, isolate)
// -> `.vsb` -> parser do score_bridge -> ScenePainter.
//
// Depende de dois artefatos não versionados; sem eles o teste é pulado em vez
// de falhar (ver README.md, seção Build):
//   tool/build_verovio_linux.sh  -> libverovio.so no verovio_flutter_bridge
//
// `verovioResourcePath()` não serve aqui: depende de path_provider, que não
// tem implementação em `flutter test`. O resourcePath aponta direto para o
// `verovio/data` do verovio_flutter_bridge, que é a mesma árvore que o zip empacota.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/verovio_render.dart';

const _submodule = '/home/mauricio/rust_projects/verovio_flutter_bridge';
const _libPath = '$_submodule/verovio/bindings/dart/libverovio.so';
const _resourcePath = '$_submodule/verovio/data';
const _scorePath = '$_submodule/corpus/mei/Grieg_Little_bird_Op43_No4.mei';

void main() {
  // `loadScoreFonts` passa pelo `rootBundle`, que exige o binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final missing = [_libPath, _resourcePath, _scorePath]
      .where((p) => !File(p).existsSync() && !Directory(p).existsSync())
      .toList();

  test('gera e desenha um .vsb a partir de um MEI do corpus', () async {
    final tmp = await Directory.systemTemp.createTemp('zywny_test');
    addTearDown(() => tmp.delete(recursive: true));

    final document = await renderScoreToVsb(
      VsbRenderRequest(
        inputPath: _scorePath,
        outputPath: '${tmp.path}/score.vsb',
        libraryPath: File(_libPath).absolute.path,
        resourcePath: Directory(_resourcePath).absolute.path,
        pageWidth: kFallbackPageWidth,
        pageHeight: kFallbackPageHeight,
      ),
    );

    expect(document.pages, isNotEmpty);
    expect(document.manifest.pageCount, document.pages.length);
    expect(document.glyphs, isNotEmpty);

    // O pintor só quebra na página real: glifos ausentes do dicionário e
    // runs de texto sem fonte carregada falham aqui, não no parse.
    await loadScoreFonts();
    final recorder = ui.PictureRecorder();
    ScenePainter(
      document.pages.first,
      document.glyphs,
      glyphCache: document.glyphCache,
    ).paint(ui.Canvas(recorder));
    recorder.endRecording().dispose();
  }, skip: missing.isEmpty ? null : 'artefatos ausentes: ${missing.join(', ')}');
}

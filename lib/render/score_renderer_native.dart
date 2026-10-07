import 'dart:async';
import 'dart:io';

import 'score_renderer.dart';
import 'verovio_paths.dart';
import 'verovio_render.dart';
import 'verovio_resources.dart';

ScoreRenderer createScoreRenderer() => NativeScoreRenderer();

/// O caminho de sempre: grava a partitura num diretório temporário, chama o
/// `libverovio` por FFI num isolate (`renderScoreToVsb`) e lê o `.vsb`.
class NativeScoreRenderer implements ScoreRenderer {
  @override
  Future<RenderedScore> render(ScoreRenderRequest request) async {
    final tmpDir = await Directory.systemTemp.createTemp('zywny');
    try {
      final inputPath = '${tmpDir.path}/${_safeName(request.fileName)}';
      await File(inputPath).writeAsBytes(request.source, flush: true);
      final outPath = '${tmpDir.path}/score.vsb';

      final document = await renderScoreToVsb(
        VsbRenderRequest(
          inputPath: inputPath,
          outputPath: outPath,
          libraryPath: findVerovioLibrary(),
          resourcePath: await verovioResourcePath(),
          pageWidth: request.pageWidth,
          pageHeight: request.pageHeight,
          options: request.options,
        ),
      );

      // `--debug` (`vsbDebug`): o .vsb some com o tmpDir no `finally`, então
      // guardamos uma cópia no diretório corrente, com data/hora no nome.
      String? debugCopyPath;
      if (request.options['vsbDebug'] == true) {
        final timestamp = DateTime.now().toIso8601String().replaceAll(
          RegExp(r'[:.]'),
          '-',
        );
        debugCopyPath = '${Directory.current.path}/score_$timestamp.vsb';
        await File(outPath).copy(debugCopyPath);
      }
      return RenderedScore(document, debugCopyPath: debugCopyPath);
    } finally {
      // O .vsb já está todo na memória; um diretório por renderização soma
      // rápido quando se experimentam opções.
      unawaited(tmpDir.delete(recursive: true).then((_) {}, onError: (_) {}));
    }
  }
}

String _safeName(String name) {
  final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return clean.isEmpty ? 'score.musicxml' : clean;
}

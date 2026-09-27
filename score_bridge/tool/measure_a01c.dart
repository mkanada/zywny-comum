// Medições de A01c: custo da compilação dos `Picture` e do repaint por cor.
//
// Roda sob o Flutter Tester (dart:ui):
//   flutter test tool/measure_a01c.dart
// Diretório dos .vsb: CORPUS_DIR (padrão ../compare/out/s08).
//
// O que cada número mede (Dart-side, sem GPU — o `flutter_tester` rasteriza
// por software, em Skia):
//   compile : `PageLayers.compileAll()` numa camada nova (mediana de 10)
//   paint   : `PageLayers.paint` gravando a página (Pictures já compilados) num
//             `PictureRecorder` + `endRecording` (mediana de 100) — é o custo
//             de CPU de um repaint depois de uma mudança de cor
//   raster  : o mesmo + `Picture.toImage` da página inteira (mediana de 30),
//             para dar a ordem de grandeza do custo de rasterizar
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

double _median(List<num> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2].toDouble();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadScoreFonts();
  final dir = Directory(
    Platform.environment['CORPUS_DIR'] ?? '../compare/out/s08',
  );
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.vsb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('medições A01c', () async {
    final rows = <List<Object>>[];
    for (final file in files) {
      final doc = VsbDocument.fromBytes(file.readAsBytesSync());
      final ids = animatableIdsFromTimemap(doc.timemap);
      for (var p = 0; p < doc.pages.length; p++) {
        final page = doc.pages[p];
        final onPage = ids.where(page.byId.containsKey).toList();

        // compile: mediana de 10, camada nova a cada vez (cache de glifos
        // já quente depois da 1ª — é o caso de uso: o do documento é
        // compartilhado entre as páginas).
        final compile = <int>[];
        PageLayers? layers;
        for (var i = 0; i < 10; i++) {
          layers?.dispose();
          layers = PageLayers(
            page,
            doc.glyphs,
            animatableIds: ids,
            glyphCache: doc.glyphCache,
          );
          final sw = Stopwatch()..start();
          layers.compileAll();
          compile.add(sw.elapsedMicroseconds);
        }
        layers!;

        Future<double> repaint(Map<String, ui.Color> overrides, int n) async {
          final times = <int>[];
          for (var i = 0; i < n; i++) {
            final sw = Stopwatch()..start();
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            layers!.applyPageTransform(canvas);
            layers.paint(canvas, overrides);
            recorder.endRecording().dispose();
            times.add(sw.elapsedMicroseconds);
          }
          return _median(times);
        }

        const red = ui.Color(0xFFFF0000);
        final one = {for (final id in onPage.take(1)) id: red};
        final many = {for (final id in onPage.take(64)) id: red};
        final paint0 = await repaint(const {}, 100);
        final paint1 = await repaint(one, 100);
        final paint64 = await repaint(many, 100);

        final raster = <int>[];
        for (var i = 0; i < 30; i++) {
          final sw = Stopwatch()..start();
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          layers.applyPageTransform(canvas);
          layers.paint(canvas, many);
          final picture = recorder.endRecording();
          final image = await picture.toImage(page.widthPx, page.heightPx);
          raster.add(sw.elapsedMicroseconds);
          image.dispose();
          picture.dispose();
        }
        rows.add([
          file.uri.pathSegments.last,
          p + 1,
          layers.segments.segmentCount,
          layers.stats.builds,
          _median(compile) / 1000,
          paint0 / 1000,
          paint1 / 1000,
          paint64 / 1000,
          _median(raster) / 1000,
        ]);
        layers.dispose();
      }
    }
    print(
      'peça;pág;segmentos;pictures;compile_ms;paint0_ms;paint1_ms;paint64_ms;raster64_ms',
    );
    for (final r in rows) {
      print(r.map((v) => v is double ? v.toStringAsFixed(3) : '$v').join(';'));
    }
    double col(int c, double Function(List<num>) f) =>
        f([for (final r in rows) r[c] as num]);
    double med(List<num> v) => _median(v);
    double mx(List<num> v) => v.reduce((a, b) => a > b ? a : b).toDouble();
    print('--- resumo (${rows.length} páginas): mediana / máximo');
    for (final (name, c) in [
      ('segmentos', 2),
      ('pictures estáticos', 3),
      ('compile_ms', 4),
      ('paint sem cor_ms', 5),
      ('paint 1 cor_ms', 6),
      ('paint 64 cores_ms', 7),
      ('raster 64 cores_ms', 8),
    ]) {
      print(
        '$name: ${col(c, med).toStringAsFixed(3)} / ${col(c, mx).toStringAsFixed(3)}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

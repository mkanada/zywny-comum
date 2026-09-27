// Prova widget-vs-harness (R05c): o que a comparação mede é o mesmo caminho
// de código que o app mostra.
//
// CRITÉRIO DE ACEITE RECORRENTE: este teste é critério de aceite de A01, A02
// e A03 também — não remova nem relaxe a tolerância sem passar por esses
// passos. Se ele quebrar num passo A, a causa provável é fundo (branco opaco
// vs. transparente), `pixelRatio`, tamanho do canvas ou fontes não carregadas.
//
// O teste renderiza a mesma página por dois chamadores do único caminho
// (`ScenePainter.paint`): o "harness" (`PictureRecorder` + `toImage`, como o
// `compare scene-to-png` faz) e um `CustomPaint` mínimo dentro de um
// `RepaintBoundary` (como o widget de produção fará em A01). A comparação é
// de bytes crus RGBA (`toByteData`), não de PNG codificado, e a diferença
// exigida é de exatamente 0 pixels.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

/// `CustomPaint` mínimo do caminho "widget": fundo branco opaco (como o
/// `scene-to-png`) + `ScenePainter.paint`. Em A01 este corpo vira as camadas
/// do `ScorePageView`; o teste continua valendo.
class _PagePainter extends CustomPainter {
  _PagePainter(this.page, this.glyphs);

  final ScenePage page;
  final Map<String, GlyphDef> glyphs;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    ScenePainter(page, glyphs).paint(canvas);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Conta pixels com algum canal RGBA diferente entre [a] e [b].
int _countDifferentPixels(ByteData a, ByteData b) {
  assert(a.lengthInBytes == b.lengthInBytes);
  final ra = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
  final rb = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
  var diff = 0;
  for (var i = 0; i < ra.length; i += 4) {
    if (ra[i] != rb[i] ||
        ra[i + 1] != rb[i + 1] ||
        ra[i + 2] != rb[i + 2] ||
        ra[i + 3] != rb[i + 3]) {
      diff++;
    }
  }
  return diff;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Sem isto o texto some dos dois lados e o teste "passa" comparando duas
    // páginas sem texto (armadilha registrada no passo).
    await loadScoreFonts();
  });

  testWidgets('widget pinta os mesmos bytes crus que o harness (0 pixels)', (
    tester,
  ) async {
    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);
    // Página 0 da Gymnopédie: 1379 nós, 842 paths, 70 elipses, 348 usos de
    // glifo e 18 runs de texto — cobre texto e glifos, não é página vazia.
    final page = doc.pages[0];
    final w = page.widthPx;
    final h = page.heightPx;

    // Caminho "harness": o mesmo que `compare scene-to-png` faz.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    ScenePainter(page, doc.glyphs).paint(canvas);
    final picture = recorder.endRecording();
    final harnessImage = (await tester.runAsync(() => picture.toImage(w, h)))!;
    final harnessBytes = (await tester.runAsync(
      () => harnessImage.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;

    // Caminho "widget": `CustomPaint` mínimo em tamanho fixo exato, capturado
    // com `pixelRatio: 1.0` (qualquer outro tamanho vira reamostragem e o
    // teste deixa de valer).
    tester.view.physicalSize = ui.Size(w.toDouble(), h.toDouble());
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: CustomPaint(
            size: ui.Size(w.toDouble(), h.toDouble()),
            painter: _PagePainter(page, doc.glyphs),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final widgetImage = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1.0),
    ))!;
    final widgetBytes = (await tester.runAsync(
      () => widgetImage.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;

    expect(harnessImage.width, w);
    expect(harnessImage.height, h);
    expect(widgetImage.width, w);
    expect(widgetImage.height, h);
    final diff = _countDifferentPixels(harnessBytes, widgetBytes);
    expect(
      diff,
      0,
      reason:
          '$diff pixels diferentes entre widget e harness '
          '(${w * h} no total)',
    );

    picture.dispose();
    harnessImage.dispose();
    widgetImage.dispose();
  });
}

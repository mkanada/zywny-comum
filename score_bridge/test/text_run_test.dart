// Testes de R04b/R04c — run de texto: linha de base, tamanho, cor (§5.4),
// mais os três alinhamentos e `letterSpacing` (R04c).
//
// Cobre os critérios de aceite 2-5 de R04b e 2-4 de R04c. O `drawParagraph`
// é observado via `RecordingCanvas` (deslocamento) e via rasterização real
// (cor).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/recording_canvas.dart';
import 'support/ttf_metrics.dart';

SceneText _run({
  String text = 'Lent',
  double x = 200,
  double y = 1000,
  double size = 405,
  SceneTextAlign align = SceneTextAlign.left,
  double letterSpacing = 0.0,
  bool bold = false,
  bool italic = false,
  String? color,
}) {
  return SceneText(
    text: text,
    x: x,
    y: y,
    size: size,
    align: align,
    letterSpacing: letterSpacing,
    bold: bold,
    italic: italic,
    family: 'Times',
    color: color,
  );
}

ScenePage _textPage(SceneChild child, {double fitScale = 1.0}) {
  return ScenePage(
    index: 0,
    width: 1000,
    height: 1000,
    contentHeight: 1000,
    viewBoxFactor: 10.0,
    viewBox: const ui.Rect.fromLTRB(0, 0, 1000, 1000),
    baseWidth: 1000,
    baseHeight: 1000,
    userScaleX: 1.0,
    userScaleY: 1.0,
    widthPx: 1000,
    heightPx: 1000,
    fit: PageFit(scale: fitScale, tx: 0.0, ty: 0.0),
    origin: ui.Offset.zero,
    root: SceneNode(className: 'g', hidden: false, children: [child]),
    elements: const [],
    byId: const {},
  );
}

SceneNode _node({String? color, List<SceneChild> children = const []}) {
  return SceneNode(
    className: 'g',
    color: color,
    hidden: false,
    children: children,
  );
}

/// Cor média dos pixels "tintados" (dominância de um canal sobre os outros
/// dois em pelo menos 30/255): ignora o branco e o cinza antialiased.
({int count, double r, double g, double b}) _inkStats(ByteData pixels) {
  var count = 0;
  var r = 0;
  var g = 0;
  var b = 0;
  for (var k = 0; k < pixels.lengthInBytes; k += 4) {
    final pr = pixels.getUint8(k);
    final pg = pixels.getUint8(k + 1);
    final pb = pixels.getUint8(k + 2);
    final dominant =
        (pr > pg + 30 && pr > pb + 30) ||
        (pg > pr + 30 && pg > pb + 30) ||
        (pb > pr + 30 && pb > pg + 30);
    if (dominant) {
      count += 1;
      r += pr;
      g += pg;
      b += pb;
    }
  }
  if (count == 0) {
    return (count: 0, r: 0, g: 0, b: 0);
  }
  return (count: count, r: r / count, g: g / count, b: b / count);
}

/// Rasteriza [child] num quadrado branco de 100×100 px (página sintética
/// com `fit.scale = 0.1`) e devolve os bytes RGBA crus.
Future<ByteData> _renderBytes(SceneChild child) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 100, 100),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  ScenePainter(_textPage(child, fitScale: 0.1), const {}).paint(canvas);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(100, 100);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<({int count, double r, double g, double b})> _paintInk(
  SceneChild child,
) async {
  return _inkStats(await _renderBytes(child));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  test('linha de base: topo em y-ascent da TTF (tol 0,5 viewBox)', () async {
    final bytes = await rootBundle.load(kScoreFontAssets[0]);
    final ttf = TtfAdvances.parse(
      bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final painter = painterForRun(_run(), const Color(0xFF000000));
    final dy = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // O topo da caixa pintada é `y - dy`: tem que bater com o ascendente
    // derivado do `hhea` da TTF carregada.
    expect(1000 - dy, closeTo(1000 - ttf.ascentOf(405), 0.5));
  });

  test('fiação: drawParagraph recebe (x, y-dy)', () {
    final run = _run();
    final dy = painterForRun(
      run,
      const Color(0xFF000000),
    ).computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final canvas = RecordingCanvas();
    ScenePainter(_textPage(run), const {}).paint(canvas);
    expect(canvas.drawParagraphs, hasLength(1));
    final call = canvas.drawParagraphs.single;
    expect(call.offset.dx, closeTo(200, 1e-9));
    expect(call.offset.dy, closeTo(1000 - dy, 1e-9));
  });

  test('escala: dobrar size dobra a largura (tol 1%)', () {
    const color = Color(0xFF000000);
    final w405 = painterForRun(_run(size: 405), color).width;
    final w810 = painterForRun(_run(size: 810), color).width;
    expect(w810 / w405, closeTo(2.0, 0.01));
  });

  test('noScaling: imune ao scaler do ambiente', () {
    const color = Color(0xFF000000);
    final ours = painterForRun(_run(), color);
    final manual = TextPainter(
      text: const TextSpan(
        text: 'Lent',
        style: TextStyle(
          fontFamily: kScoreTextFamily,
          fontSize: 405,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    expect(ours.width, manual.width);
    // Sanidade: um pintor que respeita scaler dobra com linear(2.0) — ou
    // seja, a igualdade acima é significativa, não vacuous.
    final scaled = TextPainter(
      text: const TextSpan(
        text: 'Lent',
        style: TextStyle(
          fontFamily: kScoreTextFamily,
          fontSize: 405,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(2.0),
    )..layout();
    expect(scaled.width, closeTo(manual.width * 2, 1e-6));
  });

  test('cor: herda do nó; explícita sobrepõe', () async {
    final red = await _paintInk(_node(color: '#ff0000', children: [_run()]));
    expect(red.count, greaterThan(0));
    expect(red.r, greaterThan(red.g + 30));
    expect(red.r, greaterThan(red.b + 30));

    final green = await _paintInk(
      _node(
        color: '#ff0000',
        children: [_run(color: '#00ff00')],
      ),
    );
    expect(green.count, greaterThan(0));
    expect(green.g, greaterThan(green.r + 30));
    expect(green.g, greaterThan(green.b + 30));
  });

  test('alinhamentos sem letterSpacing: x, x-w/2, x-w', () {
    const color = Color(0xFF000000);
    final w = painterForRun(_run(), color).width;
    final cases = {
      SceneTextAlign.left: 200.0,
      SceneTextAlign.center: 200.0 - w / 2,
      SceneTextAlign.right: 200.0 - w,
    };
    for (final entry in cases.entries) {
      final canvas = RecordingCanvas();
      ScenePainter(_textPage(_run(align: entry.key)), const {}).paint(canvas);
      expect(canvas.drawParagraphs, hasLength(1));
      expect(
        canvas.drawParagraphs.single.offset.dx,
        closeTo(entry.value, 1e-6),
      );
    }
  });

  test('alinhamentos com letterSpacing 40: largura à mão', () async {
    // Largura esperada calculada à mão: soma dos avanços + n×ls, com o
    // espaçamento final incluído (semântica do SVG/`resvg`).
    final bytes = await rootBundle.load(kScoreFontAssets[0]);
    final ttf = TtfAdvances.parse(
      bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    const text = 'Lent';
    final hand = ttf.widthOf(text, 405) + text.runes.length * 40.0;
    const color = Color(0xFF000000);
    final w = painterForRun(_run(text: text, letterSpacing: 40.0), color).width;
    // Conclusão R04c (Flutter 3.47.4): o Flutter INCLUI o espaçamento
    // final no width — sem compensação em `center`/`right`.
    expect(w, closeTo(hand, 1e-6));
    final cases = {
      SceneTextAlign.left: 200.0,
      SceneTextAlign.center: 200.0 - hand / 2,
      SceneTextAlign.right: 200.0 - hand,
    };
    for (final entry in cases.entries) {
      final canvas = RecordingCanvas();
      ScenePainter(
        _textPage(_run(text: text, align: entry.key, letterSpacing: 40.0)),
        const {},
      ).paint(canvas);
      expect(
        canvas.drawParagraphs.single.offset.dx,
        closeTo(entry.value, 1e-6),
      );
    }
  });

  test('dedilhado real: centro sobre x (tol 0,5 viewBox)', () {
    final bytes = File('../compare/out/s08/Chopin_Etude_Op10_No9.vsb')
        .readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);
    SceneText? fingering;
    for (final child in doc.pages[0].root.children) {
      fingering = _firstCenter303(child);
      if (fingering != null) {
        break;
      }
    }
    expect(fingering, isNotNull, reason: 'sem dedilhado 303/center na p1');
    final run = fingering!;
    final w = painterForRun(run, const Color(0xFF000000)).width;
    final canvas = RecordingCanvas();
    ScenePainter(_textPage(run), doc.glyphs).paint(canvas);
    expect(canvas.drawParagraphs, hasLength(1));
    final left = canvas.drawParagraphs.single.offset.dx;
    // O centro do run pintado cai sobre o `x` do formato.
    expect(left + w / 2, closeTo(run.x, 0.5));
  });

  test('4 estilos: imagens duas a duas diferentes', () async {
    // Guarda contra TTF não registrada (itálico/negrito sintético): uma
    // igualdade significa que uma das faces não foi usada.
    final images = <String, Uint8List>{};
    for (final style in const [
      (false, false),
      (false, true),
      (true, false),
      (true, true),
    ]) {
      final bytes = await _renderBytes(
        _run(text: 'Agitato', size: 200, bold: style.$1, italic: style.$2),
      );
      images['${style.$1}/${style.$2}'] = bytes.buffer.asUint8List();
    }
    final keys = images.keys.toList();
    for (var a = 0; a < keys.length; a++) {
      for (var b = a + 1; b < keys.length; b++) {
        expect(
          images[keys[a]],
          isNot(equals(images[keys[b]])),
          reason: '${keys[a]} == ${keys[b]}: face não registrada?',
        );
      }
    }
  });

  test('4 estilos: largura bate com a TTF daquele arquivo (<1%)', () async {
    // Pega itálico sintético: ele preserva a largura da regular, que difere
    // da itálica real.
    const runs = [
      (false, false, 0),
      (false, true, 1),
      (true, false, 2),
      (true, true, 3),
    ];
    for (final (bold, italic, asset) in runs) {
      final bytes = await rootBundle.load(kScoreFontAssets[asset]);
      final ttf = TtfAdvances.parse(
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      const text = 'Agitato';
      const size = 405.0;
      final expected = ttf.widthOf(text, size);
      final actual = painterForRun(
        _run(text: text, size: size, bold: bold, italic: italic),
        const Color(0xFF000000),
      ).width;
      expect(
        (actual - expected).abs() / expected,
        lessThan(0.01),
        reason: 'estilo $bold/$italic (asset $asset)',
      );
    }
  });
}

/// Primeiro run `t` com `size: 303` e `align: center` na subárvore (os
/// dedilhados da Étude, p. ex. '5' sobre a nota).
SceneText? _firstCenter303(SceneChild child) {
  if (child is SceneText) {
    if (child.size == 303 && child.align == SceneTextAlign.center) {
      return child;
    }
    return null;
  }
  if (child is SceneNode) {
    for (final grand in child.children) {
      final found = _firstCenter303(grand);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

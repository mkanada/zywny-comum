// Testes de R02c — traço, opacidade, `lineCap`/`lineJoin` e tracejado (§5.2).
//
// Cobre os critérios de aceite 2-7 do passo, usando o `RecordingCanvas`
// de `support/recording_canvas.dart`.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/recording_canvas.dart';

ScenePath _lineShape({
  double length = 1000,
  ScenePaint fill = ScenePaint.none,
  ScenePaint stroke = ScenePaint.inherit,
  double fillOpacity = 1.0,
  double strokeOpacity = 1.0,
  double? strokeWidth = 1.0,
  SceneLineCap lineCap = SceneLineCap.defaultCap,
  SceneLineJoin lineJoin = SceneLineJoin.defaultJoin,
  SceneDash? dash,
}) {
  return ScenePath(
    paths: [
      BezierPath(
        closed: false,
        v: Float64List.fromList([0, 0, length, 0]),
        i: Float64List.fromList([0, 0, 0, 0]),
        o: Float64List.fromList([0, 0, 0, 0]),
      ),
    ],
    fill: fill,
    fillOpacity: fillOpacity,
    stroke: stroke,
    strokeWidth: strokeWidth,
    strokeOpacity: strokeOpacity,
    lineCap: lineCap,
    lineJoin: lineJoin,
    dash: dash,
  );
}

ScenePage _singleShapePage(SceneChild shape, {double fitScale = 1.0}) {
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
    root: SceneNode(className: 'g', hidden: false, children: [shape]),
    elements: const [],
    byId: const {},
  );
}

RecordingCanvas _paintSingle(SceneChild shape, {double fitScale = 1.0}) {
  final canvas = RecordingCanvas();
  ScenePainter(
    _singleShapePage(shape, fitScale: fitScale),
    const {},
  ).paint(canvas);
  return canvas;
}

double _totalLength(ui.Path path) {
  var total = 0.0;
  for (final m in path.computeMetrics()) {
    total += m.length;
  }
  return total;
}

int _contourCount(ui.Path path) => path.computeMetrics().toList().length;

/// Primeira forma com `dash` em ordem de documento (qualquer página).
SceneShape? _firstDashedShape(SceneNode root) {
  for (final child in root.children) {
    if (child is SceneShape && child.dash != null) {
      return child;
    }
    if (child is SceneNode) {
      final found = _firstDashedShape(child);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

void main() {
  test('canal: 9 combinações de fill × stroke dão 0, 1 ou 2 drawPath', () {
    const red = ColorPaint('#ff0000');
    const green = ColorPaint('#00ff00');
    const blue = ColorPaint('#0000ff');
    const black = ui.Color(0xFF000000);

    // (fill, stroke, drawPaths esperados, cores esperadas na ordem
    // [fill, stroke] — preenchimento primeiro, traço depois, ordem do SVG).
    final cases = [
      (ScenePaint.none, ScenePaint.none, <ui.Color>[]),
      (ScenePaint.none, ScenePaint.inherit, [black]),
      (ScenePaint.none, green, [const ui.Color(0xFF00FF00)]),
      (ScenePaint.inherit, ScenePaint.none, [black]),
      (ScenePaint.inherit, ScenePaint.inherit, [black, black]),
      (ScenePaint.inherit, green, [black, const ui.Color(0xFF00FF00)]),
      (red, ScenePaint.none, [const ui.Color(0xFFFF0000)]),
      (red, ScenePaint.inherit, [const ui.Color(0xFFFF0000), black]),
      (red, blue, [const ui.Color(0xFFFF0000), const ui.Color(0xFF0000FF)]),
    ];

    for (var k = 0; k < cases.length; k++) {
      final (fill, stroke, expected) = cases[k];
      final shape = _lineShape(fill: fill, stroke: stroke);
      final canvas = _paintSingle(shape);
      expect(
        canvas.drawPaths.map((c) => c.paint.color).toList(),
        expected,
        reason: 'caso $k (fill=$fill, stroke=$stroke)',
      );
      // Estilo de cada chamada: fill primeiro, stroke depois.
      if (expected.length == 2) {
        expect(
          canvas.drawPaths[0].paint.style,
          ui.PaintingStyle.fill,
          reason: 'caso $k: primeira chamada é o preenchimento',
        );
        expect(
          canvas.drawPaths[1].paint.style,
          ui.PaintingStyle.stroke,
          reason: 'caso $k: segunda chamada é o traço',
        );
      } else if (expected.length == 1) {
        final wantStyle = identical(fill, ScenePaint.none)
            ? ui.PaintingStyle.stroke
            : ui.PaintingStyle.fill;
        expect(
          canvas.drawPaths.single.paint.style,
          wantStyle,
          reason: 'caso $k: canal único',
        );
      }
    }
  });

  test(
    'largura: strokeWidth 18 fica em unidades de viewBox (sem fit.scale)',
    () {
      // fit.scale = 0.1 (página A4 típica): se o pintor multiplicasse pela
      // escala, sairia 1.8 em vez de 18.
      final shape = _lineShape(
        fill: ScenePaint.none,
        stroke: ScenePaint.inherit,
        strokeWidth: 18.0,
      );
      final canvas = _paintSingle(shape, fitScale: 0.1);
      expect(canvas.drawPaths, hasLength(1));
      expect(canvas.drawPaths.single.paint.strokeWidth, 18.0);
      expect(canvas.drawPaths.single.paint.style, ui.PaintingStyle.stroke);
    },
  );

  test('opacidade: fillOpacity 0.5 sobre #ff0000 dá alfa 128 (round)', () {
    final shape = _lineShape(
      fill: const ColorPaint('#ff0000'),
      stroke: ScenePaint.none,
      fillOpacity: 0.5,
    );
    final canvas = _paintSingle(shape);
    expect(canvas.drawPaths, hasLength(1));
    final color = canvas.drawPaths.single.paint.color;
    // Arredondamento metade para cima: 255 × 0.5 = 127.5 → 128.
    expect((color.a * 255.0).round(), 128);
    expect((color.r * 255.0).round(), 255);
    expect((color.g * 255.0).round(), 0);
    expect((color.b * 255.0).round(), 0);
  });

  test('tracejado: reta de 1000 com dash [36, 72] dá 10 traços e 352', () {
    const dash = SceneDash(36, 72);
    final shape = _lineShape(length: 1000, dash: dash);
    final base = shape.path;
    expect(_totalLength(base), closeTo(1000.0, 1e-6));

    final dashed = applyDash(base, dash);
    // 1000 = 9 × 108 + 28: 9 traços completos de 36 + resto de 28.
    // Total aceso = 9 × 36 + 28 = 352; contornos = 9 + 1 = 10.
    // Tolerância 0.5: `computeMetrics` mede o comprimento por flattening do
    // Skia (erro observado ≈ 0.18 em 352), então a comparação é por
    // proximidade, não exata — é o "ceil/floor do esperado" do critério 5.
    expect(_contourCount(dashed), 10);
    expect(_totalLength(dashed), closeTo(352.0, 0.5));

    // O primeiro traço começa exatamente no ponto inicial (0, 0).
    final first = dashed.computeMetrics().first;
    final start = first.getTangentForOffset(0.0)!.position;
    expect(start.dx, closeTo(0.0, 1e-9));
    expect(start.dy, closeTo(0.0, 1e-9));
    // Tolerância 0.5 pelo mesmo erro de flattening (observado ≈ 0.11).
    expect(first.length, closeTo(36.0, 0.5));

    // Pelo pintor: fill=none, então só o traço tracejado é desenhado.
    final canvas = _paintSingle(shape);
    expect(canvas.drawPaths, hasLength(1));
    final drawn = canvas.drawPaths.single;
    expect(drawn.paint.style, ui.PaintingStyle.stroke);
    expect(_contourCount(drawn.path), 10);
    expect(_totalLength(drawn.path), closeTo(352.0, 0.5));
  });

  test('caso real: primeiro octave tracejado do Chopin Étude Op.10 No.9', () {
    final bytes = File('../compare/out/s08/Chopin_Etude_Op10_No9.vsb')
        .readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);

    SceneShape? dashed;
    for (final page in doc.pages) {
      dashed = _firstDashedShape(page.root);
      if (dashed != null) {
        break;
      }
    }
    expect(dashed, isNotNull, reason: 'nenhuma forma com dash no .vsb');
    expect(dashed!.dash!.length, 36.0);
    expect(dashed.dash!.gap, 72.0);

    // Comprimento da linha de base e contagem esperada pela fórmula
    // fechada: contornos = ceil(len / 108), total aceso =
    // floor(len / 108) × 36 + min(resto, 36).
    final ui.Path base;
    if (dashed is ScenePath) {
      base = dashed.path;
    } else {
      fail('forma tracejada real não é ScenePath: ${dashed.runtimeType}');
    }
    final len = _totalLength(base);
    expect(len, greaterThan(0));
    const period = 36.0 + 72.0;
    final full = (len / period).floor();
    final rest = len - full * period;
    final expectedCount = full + (rest > 0 ? 1 : 0);
    final expectedLit = full * 36.0 + (rest <= 0 ? 0 : rest.clamp(0, 36.0));

    final result = applyDash(base, dashed.dash!);
    expect(_contourCount(result), expectedCount);
    // Tolerância 2.0: mesmo erro de flattening do Skia do teste sintético,
    // proporcional ao comprimento (observado ≈ 0.78 em 1836).
    expect(_totalLength(result), closeTo(expectedLit, 2.0));

    // Pelo pintor: octave tem fill=none, então 1 drawPath de traço.
    final canvas = _paintSingle(dashed);
    expect(canvas.drawPaths, hasLength(1));
    expect(canvas.drawPaths.single.paint.style, ui.PaintingStyle.stroke);
    expect(_contourCount(canvas.drawPaths.single.path), expectedCount);
  });

  test('default: sem lineCap/lineJoin vira butt/miter', () {
    final shape = _lineShape(
      fill: ScenePaint.none,
      stroke: ScenePaint.inherit,
      lineCap: SceneLineCap.defaultCap,
      lineJoin: SceneLineJoin.defaultJoin,
    );
    final canvas = _paintSingle(shape);
    expect(canvas.drawPaths, hasLength(1));
    expect(canvas.drawPaths.single.paint.strokeCap, ui.StrokeCap.butt);
    expect(canvas.drawPaths.single.paint.strokeJoin, ui.StrokeJoin.miter);
  });

  test('mapeamento explícito de cap/join e anti-alias ligado', () {
    final shape = _lineShape(
      fill: const ColorPaint('#000000'),
      stroke: ScenePaint.inherit,
      lineCap: SceneLineCap.round,
      lineJoin: SceneLineJoin.round,
    );
    final canvas = _paintSingle(shape);
    expect(canvas.drawPaths, hasLength(2));
    expect(canvas.drawPaths[0].paint.isAntiAlias, isTrue);
    expect(canvas.drawPaths[1].paint.isAntiAlias, isTrue);
    expect(canvas.drawPaths[1].paint.strokeCap, ui.StrokeCap.round);
    expect(canvas.drawPaths[1].paint.strokeJoin, ui.StrokeJoin.round);

    final square = _paintSingle(
      _lineShape(
        fill: ScenePaint.none,
        stroke: ScenePaint.inherit,
        lineCap: SceneLineCap.square,
        lineJoin: SceneLineJoin.bevel,
      ),
    );
    expect(square.drawPaths.single.paint.strokeCap, ui.StrokeCap.square);
    expect(square.drawPaths.single.paint.strokeJoin, ui.StrokeJoin.bevel);
  });
}

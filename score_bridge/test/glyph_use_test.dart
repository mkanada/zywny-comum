// Testes de R03b — instâncias `u`: transformação, traço e herança (§5.3).
//
// Cobre os critérios de aceite 2-5 do passo, usando o `RecordingCanvas`
// de `support/recording_canvas.dart` e o fixture `erik-satie.vsb`
// (16 glifos no dicionário, 417 usos no total).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/recording_canvas.dart';

SceneGlyphUse _glyphUse({
  String glyphId = 'Leipzig:E0A3',
  double x = 4164,
  double y = 2344,
  double sx = 0.72,
  double sy = 0.72,
  ScenePaint fill = ScenePaint.inherit,
  ScenePaint stroke = ScenePaint.inherit,
  double? strokeWidth,
}) {
  return SceneGlyphUse(
    glyphId: glyphId,
    x: x,
    y: y,
    sx: sx,
    sy: sy,
    fill: fill,
    fillOpacity: 1.0,
    stroke: stroke,
    strokeWidth: strokeWidth,
    strokeOpacity: 1.0,
    lineCap: SceneLineCap.defaultCap,
    lineJoin: SceneLineJoin.defaultJoin,
    dash: null,
  );
}

ScenePage _singleGlyphPage(SceneChild child, {double fitScale = 1.0}) {
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

SceneNode _node({
  String? id,
  String? color,
  List<SceneChild> children = const [],
}) {
  return SceneNode(
    id: id,
    className: 'g',
    color: color,
    hidden: false,
    children: children,
  );
}

/// Todos os `glyphId` usados na árvore de [root], em ordem de documento.
List<String> _usedGlyphIds(SceneNode root) {
  final ids = <String>[];
  void walk(SceneNode node) {
    for (final child in node.children) {
      if (child is SceneNode) {
        walk(child);
      } else if (child is SceneGlyphUse) {
        ids.add(child.glyphId);
      }
    }
  }

  walk(root);
  return ids;
}

/// `GlyphCache` que conta chamadas a `pathFor` (critério 5: 417 usos).
class _CountingGlyphCache extends GlyphCache {
  _CountingGlyphCache(super.glyphs);

  int calls = 0;

  @override
  ui.Path pathFor(String glyphId) {
    calls += 1;
    return super.pathFor(glyphId);
  }
}

void main() {
  late VsbDocument doc;

  setUpAll(() {
    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    doc = VsbDocument.fromBytes(bytes);
  });

  test(
    'posicionamento: E0A3 em (4164,2344) s=0.72 bate com bbox (tol 1.0)',
    () {
      const x = 4164.0;
      const y = 2344.0;
      const s = 0.72;
      final def = doc.glyphs['Leipzig:E0A3']!;
      final contour = def.bbox.toContourRect();
      final expected = ui.Rect.fromLTRB(
        x + contour.left * s,
        y + contour.top * s,
        x + contour.right * s,
        y + contour.bottom * s,
      );

      final canvas = RecordingCanvas();
      ScenePainter(_singleGlyphPage(_glyphUse()), doc.glyphs).paint(canvas);

      // Um uso com fill+stroke herdados produz 2 drawPath (critério 3).
      expect(canvas.drawPaths, hasLength(2));
      final call = canvas.drawPaths.first;
      final bounds = call.path.getBounds();
      // O `Path` está em espaço de glifo; a transformação ativa (fit
      // identidade + translate/scale do uso) o leva a viewBox.
      final mapped = ui.Rect.fromLTRB(
        call.map(bounds.left, bounds.top).dx,
        call.map(bounds.left, bounds.top).dy,
        call.map(bounds.right, bounds.bottom).dx,
        call.map(bounds.right, bounds.bottom).dy,
      );
      expect(mapped.left, closeTo(expected.left, 1.0));
      expect(mapped.top, closeTo(expected.top, 1.0));
      expect(mapped.right, closeTo(expected.right, 1.0));
      expect(mapped.bottom, closeTo(expected.bottom, 1.0));
    },
  );

  test('traço: dois drawPath por uso, strokeWidth 1.0 dentro do scale', () {
    final canvas = RecordingCanvas();
    ScenePainter(_singleGlyphPage(_glyphUse()), doc.glyphs).paint(canvas);

    expect(canvas.drawPaths, hasLength(2));
    final fillCall = canvas.drawPaths[0];
    final strokeCall = canvas.drawPaths[1];
    expect(fillCall.paint.style, ui.PaintingStyle.fill);
    expect(strokeCall.paint.style, ui.PaintingStyle.stroke);
    // 1,0 no espaço do glifo (dentro do scale ativo).
    expect(strokeCall.paint.strokeWidth, 1.0);
    // O scale ativo é o do uso (fit identidade neste teste).
    expect(strokeCall.transform.a, closeTo(0.72, 1e-9));
    expect(strokeCall.transform.d, closeTo(0.72, 1e-9));
    // save/restore balanceados (página + 1 uso).
    expect(canvas.getSaveCount(), 1);
  });

  test(
    'herança: nó vermelho pinta os dois canais; fill explícito sobrepõe',
    () {
      final red = _node(color: '#ff0000', children: [_glyphUse()]);
      var canvas = RecordingCanvas();
      ScenePainter(_singleGlyphPage(red), doc.glyphs).paint(canvas);
      expect(canvas.drawPaths, hasLength(2));
      expect(canvas.drawPaths[0].paint.color, const ui.Color(0xFFFF0000));
      expect(canvas.drawPaths[1].paint.color, const ui.Color(0xFFFF0000));

      // `fill` explícito ignora a herança só no preenchimento.
      final mixed = _node(
        color: '#ff0000',
        children: [_glyphUse(fill: const ColorPaint('#00ff00'))],
      );
      canvas = RecordingCanvas();
      ScenePainter(_singleGlyphPage(mixed), doc.glyphs).paint(canvas);
      expect(canvas.drawPaths, hasLength(2));
      expect(canvas.drawPaths[0].paint.color, const ui.Color(0xFF00FF00));
      expect(canvas.drawPaths[1].paint.color, const ui.Color(0xFFFF0000));
    },
  );

  test('strokeWidth explícito: valor em viewBox dividido por sy', () {
    // 7.2 viewBox com sy=0.72 vira 10.0 no espaço do glifo.
    final canvas = RecordingCanvas();
    ScenePainter(
      _singleGlyphPage(_glyphUse(strokeWidth: 7.2)),
      doc.glyphs,
    ).paint(canvas);
    expect(canvas.drawPaths, hasLength(2));
    expect(canvas.drawPaths[1].paint.strokeWidth, closeTo(10.0, 1e-9));
  });

  test('reuso: usos consecutivos com a mesma cor reusam o Paint', () {
    final root = _node(
      color: '#ff0000',
      children: [_glyphUse(x: 100), _glyphUse(x: 200)],
    );
    final canvas = RecordingCanvas();
    ScenePainter(_singleGlyphPage(root), doc.glyphs).paint(canvas);
    expect(canvas.drawPaths, hasLength(4));
    // fill do uso 1 e do uso 2: mesma instância; idem para o traço.
    expect(
      identical(canvas.drawPaths[0].paint, canvas.drawPaths[2].paint),
      isTrue,
    );
    expect(
      identical(canvas.drawPaths[1].paint, canvas.drawPaths[3].paint),
      isTrue,
    );
  });

  test('contagem: página inteira chama pathFor 417× mas constrói 16 Path', () {
    var uses = 0;
    for (final page in doc.pages) {
      uses += _usedGlyphIds(page.root).length;
    }
    expect(uses, 417);

    final cache = _CountingGlyphCache(doc.glyphs);
    for (final page in doc.pages) {
      final canvas = RecordingCanvas();
      ScenePainter(page, doc.glyphs, glyphCache: cache).paint(canvas);
    }
    expect(cache.calls, 417);
    expect(cache.builtCount, 16);
    expect(cache.builtCount, doc.glyphs.length);
  });
}

// Testes de R02a — geometria `v`/`i`/`o` -> `ui.Path` (§4.1/§5.2).
//
// Cobre os critérios de aceite 2-7 do passo:
// reta, Bézier conhecido, fechamento, forma real do corpus, rect/elipse e
// cache por objeto.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

BezierPath _bezier(
  List<double> v,
  List<double> tangentes, {
  required bool closed,
  List<double>? i,
  List<double>? o,
}) {
  return BezierPath(
    closed: closed,
    v: Float64List.fromList(v),
    i: Float64List.fromList(i ?? tangentes),
    o: Float64List.fromList(o ?? tangentes),
  );
}

double _cubic1D(double p0, double c1, double c2, double p1, double t) {
  final u = 1 - t;
  return u * u * u * p0 +
      3 * u * u * t * c1 +
      3 * u * t * t * c2 +
      t * t * t * p1;
}

SceneRect _rect(double x, double y, double w, double h, double rx) {
  return SceneRect(
    x: x,
    y: y,
    w: w,
    h: h,
    rx: rx,
    fill: ScenePaint.inherit,
    fillOpacity: 1.0,
    stroke: ScenePaint.inherit,
    strokeWidth: null,
    strokeOpacity: 1.0,
    lineCap: SceneLineCap.defaultCap,
    lineJoin: SceneLineJoin.defaultJoin,
    dash: null,
  );
}

SceneEllipse _ellipse(double cx, double cy, double rx, double ry) {
  return SceneEllipse(
    cx: cx,
    cy: cy,
    rx: rx,
    ry: ry,
    fill: ScenePaint.inherit,
    fillOpacity: 1.0,
    stroke: ScenePaint.inherit,
    strokeWidth: null,
    strokeOpacity: 1.0,
    lineCap: SceneLineCap.defaultCap,
    lineJoin: SceneLineJoin.defaultJoin,
    dash: null,
  );
}

void main() {
  test('reta: 2 vértices com tangentes zero tem comprimento 100', () {
    final sub = _bezier([0, 0, 100, 0], [0, 0, 0, 0], closed: false);
    final path = pathFromBeziers([sub]);
    final metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.length, closeTo(100.0, 1e-9));
    expect(path.getBounds(), const Rect.fromLTRB(0, 0, 100, 0));
  });

  test(
    'Bézier conhecido: 10 pontos da fórmula cúbica via getTangentForOffset',
    () {
      // Controles sobre a reta com velocidade constante (1/3 e 2/3): B(t) é
      // linear em t, então a parametrização por arco (getTangentForOffset)
      // coincide com t e a comparação é exata — qualquer erro seria da
      // conversão, não da parametrização. Escala 10 (não 100) para que o
      // erro absoluto de flattening do Skia (~2e-8 por unidade) caiba em
      // 1e-6.
      const p0x = 0.0;
      const p0y = 0.0;
      const p1x = 10.0;
      const p1y = 0.0;
      const c1x = 10.0 / 3.0;
      const c1y = 0.0;
      const c2x = 20.0 / 3.0;
      const c2y = 0.0;
      final sub = _bezier(
        [p0x, p0y, p1x, p1y],
        [0, 0, 0, 0],
        closed: false,
        o: [c1x - p0x, c1y - p0y, 0, 0],
        i: [0, 0, c2x - p1x, c2y - p1y],
      );
      final path = pathFromBeziers([sub]);
      final metric = path.computeMetrics().single;
      expect(metric.length, closeTo(10.0, 1e-9));
      for (var j = 0; j < 10; j++) {
        final t = j / 10.0;
        final expectedX = _cubic1D(p0x, c1x, c2x, p1x, t);
        final expectedY = _cubic1D(p0y, c1y, c2y, p1y, t);
        final tangent = metric.getTangentForOffset(metric.length * t)!;
        expect(tangent.position.dx, closeTo(expectedX, 1e-6));
        expect(tangent.position.dy, closeTo(expectedY, 1e-6));
      }

      // Curva de verdade (lombada): o ponto médio sai do eixo, provando que
      // tangentes não nulas viram curva e não reta.
      final bump = _bezier(
        [0, 0, 100, 0],
        [0, 0, 0, 0],
        closed: false,
        o: [0, 50, 0, 0],
        i: [0, 0, 0, 50],
      );
      final bumpPath = pathFromBeziers([bump]);
      final bumpMetric = bumpPath.computeMetrics().single;
      expect(bumpMetric.length, greaterThan(100.0));
      expect(_cubic1D(0, 50, 50, 0, 0.5), closeTo(37.5, 1e-9));
      expect(bumpPath.getBounds().top, closeTo(0.0, 1e-9));
      expect(bumpPath.getBounds().bottom, greaterThan(30.0));
    },
  );

  test('fechamento: versão fechada é mais longa e contém o interior', () {
    // Lente de 2 vértices: ida com lombada para cima, volta com lombada
    // para baixo. A versão aberta fecha implicitamente pela reta y=0 (só a
    // lombada superior conta); a fechada soma a cúbica de volta, então é
    // mais longa e contém um ponto da metade inferior que a aberta não
    // contém. (`Path.contains` fecha implicitamente paths abertos, por isso
    // um triângulo de tangentes zero não serviria: aberta e fechada
    // conteriam o mesmo.)
    final v = [0.0, 0.0, 100.0, 0.0];
    final o = [0.0, 50.0, 0.0, -50.0];
    final i = [0.0, -50.0, 0.0, 50.0];
    final open = pathFromBeziers([
      _bezier(v, [0, 0, 0, 0], closed: false, o: o, i: i),
    ]);
    final closed = pathFromBeziers([
      _bezier(v, [0, 0, 0, 0], closed: true, o: o, i: i),
    ]);
    final openLength = open.computeMetrics().single.length;
    final closedLength = closed.computeMetrics().single.length;
    expect(closedLength, greaterThan(openLength));
    expect(closed.contains(const Offset(50, -20)), isTrue);
    expect(open.contains(const Offset(50, -20)), isFalse);
  });

  test('forma real do corpus: primeira ScenePath dentro da bbox do nó pai', () {
    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);
    final found = _firstPathWithParent(doc.pages.first.root);
    expect(found, isNotNull);
    final (shape, parentBbox) = found!;
    expect(parentBbox, isNotNull);
    final bounds = shape.path.getBounds();
    final stroke = shape.strokeWidth ?? 1.0;
    final tol = stroke / 2.0;
    expect(bounds.left, greaterThanOrEqualTo(parentBbox!.left - tol));
    expect(bounds.top, greaterThanOrEqualTo(parentBbox.top - tol));
    expect(bounds.right, lessThanOrEqualTo(parentBbox.right + tol));
    expect(bounds.bottom, lessThanOrEqualTo(parentBbox.bottom + tol));
  });

  test('rect e elipse: bounds exatos; rx > 0 arredonda os cantos', () {
    final rect = _rect(10, 20, 100, 50, 0);
    expect(rect.path.getBounds(), const Rect.fromLTRB(10, 20, 110, 70));

    final ellipse = _ellipse(50, 60, 30, 20);
    expect(ellipse.path.getBounds(), const Rect.fromLTRB(20, 40, 80, 80));

    final rounded = _rect(10, 20, 100, 50, 10);
    expect(rounded.path.getBounds(), const Rect.fromLTRB(10, 20, 110, 70));
    // Canto exato fica fora por causa do arredondamento; um ponto logo
    // abaixo da aresta superior e o centro seguem dentro.
    expect(rounded.path.contains(const Offset(10, 20)), isFalse);
    expect(rounded.path.contains(const Offset(60, 22)), isTrue);
    expect(rounded.path.contains(const Offset(60, 45)), isTrue);
  });

  test('cache: getter path devolve a mesma instância', () {
    final shape = ScenePath(
      paths: [
        _bezier([0, 0, 100, 0], [0, 0, 0, 0], closed: false),
      ],
      fill: ScenePaint.inherit,
      fillOpacity: 1.0,
      stroke: ScenePaint.inherit,
      strokeWidth: null,
      strokeOpacity: 1.0,
      lineCap: SceneLineCap.defaultCap,
      lineJoin: SceneLineJoin.defaultJoin,
      dash: null,
    );
    expect(identical(shape.path, shape.path), isTrue);

    final rect = _rect(0, 0, 10, 10, 0);
    expect(identical(rect.path, rect.path), isTrue);

    final ellipse = _ellipse(5, 5, 5, 5);
    expect(identical(ellipse.path, ellipse.path), isTrue);

    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);
    final glyph = doc.glyphs.values.first;
    expect(identical(glyph.path, glyph.path), isTrue);
  });
}

/// Primeira `ScenePath` em ordem de documento + bbox do nó pai direto.
(ScenePath, Rect?)? _firstPathWithParent(SceneNode root) {
  for (final child in root.children) {
    if (child is ScenePath) {
      return (child, root.bbox);
    }
    if (child is SceneNode) {
      final found = _firstPathWithParent(child);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

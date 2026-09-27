// `Canvas` de teste que grava chamadas (R02b §4).
//
// Usado pelos critérios 2-7 de R02b e pelos passos seguintes. Grava
// `drawPath` (com a `Paint` efetiva e um snapshot da transformação ativa),
// `drawParagraph` (R04b, com o deslocamento e o snapshot), as operações de
// salvamento (`save`/`restore`) e as de transformação
// (`translate`/`scale`/`rotate`/`transform`/`skew`). Todo o resto da
// interface `Canvas` é no-op.
//
// A transformação corrente é uma afim 2D mantida por composição, na mesma
// ordem do `Canvas` real (pós-multiplicação), permitindo mapear pontos de
// viewBox para o espaço de saída sem backend gráfico.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Transformação afim 2D `(x, y) -> (a*x + b*y + tx, c*x + d*y + ty)`.
class AffineTransform {
  AffineTransform(this.a, this.b, this.c, this.d, this.tx, this.ty);

  AffineTransform.identity() : a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;

  double a;
  double b;
  double c;
  double d;
  double tx;
  double ty;

  AffineTransform clone() => AffineTransform(a, b, c, d, tx, ty);

  void translate(double dx, double dy) {
    tx = a * dx + b * dy + tx;
    ty = c * dx + d * dy + ty;
  }

  void scale(double sx, double sy) {
    a *= sx;
    b *= sy;
    c *= sx;
    d *= sy;
  }

  void rotateRadians(double radians) {
    final cosT = math.cos(radians);
    final sinT = math.sin(radians);
    final na = a * cosT + b * sinT;
    final nb = -a * sinT + b * cosT;
    final nc = c * cosT + d * sinT;
    final nd = -c * sinT + d * cosT;
    a = na;
    b = nb;
    c = nc;
    d = nd;
  }

  void skew(double sx, double sy) {
    final tanX = math.tan(sx);
    final tanY = math.tan(sy);
    final na = a + b * tanY;
    final nb = a * tanX + b;
    final nc = c + d * tanY;
    final nd = c * tanX + d;
    a = na;
    b = nb;
    c = nc;
    d = nd;
  }

  /// Compõe uma matriz 4x4 coluna-major (`Canvas.transform`): usa só a parte
  /// afim 2D (`m[0]`, `m[1]`, `m[4]`, `m[5]`, `m[12]`, `m[13]`).
  void concatMatrix4(Float64List m) {
    final a4 = m[0];
    final c4 = m[1];
    final b4 = m[4];
    final d4 = m[5];
    final tx4 = m[12];
    final ty4 = m[13];
    final na = a * a4 + b * c4;
    final nb = a * b4 + b * d4;
    final ntx = a * tx4 + b * ty4 + tx;
    final nc = c * a4 + d * c4;
    final nd = c * b4 + d * d4;
    final nty = c * tx4 + d * ty4 + ty;
    a = na;
    b = nb;
    c = nc;
    d = nd;
    tx = ntx;
    ty = nty;
  }

  ui.Offset map(double x, double y) =>
      ui.Offset(a * x + b * y + tx, c * x + d * y + ty);

  Float64List toMatrix4() {
    return Float64List.fromList([
      a, c, 0, 0, //
      b, d, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1,
    ]);
  }
}

/// Uma chamada `drawPath` gravada, com snapshot da transformação ativa.
class DrawPathCall {
  DrawPathCall(this.path, this.paint, this.transform);

  final ui.Path path;
  final ui.Paint paint;
  final AffineTransform transform;

  ui.Offset map(double x, double y) => transform.map(x, y);
}

/// Uma chamada `drawParagraph` gravada (R04b), com o deslocamento pedido e
/// um snapshot da transformação ativa.
class DrawParagraphCall {
  DrawParagraphCall(this.paragraph, this.offset, this.transform);

  final ui.Paragraph paragraph;
  final ui.Offset offset;
  final AffineTransform transform;

  ui.Offset map(double x, double y) => transform.map(x, y);
}

class RecordingCanvas implements ui.Canvas {
  final List<DrawPathCall> drawPaths = [];
  final List<DrawParagraphCall> drawParagraphs = [];
  final List<String> ops = [];

  final List<AffineTransform> _stack = [AffineTransform.identity()];

  AffineTransform get currentTransform => _stack.last;

  ui.Offset transformPoint(double x, double y) => _stack.last.map(x, y);

  @override
  void save() {
    ops.add('save');
    _stack.add(_stack.last.clone());
  }

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    ops.add('saveLayer');
    _stack.add(_stack.last.clone());
  }

  @override
  void restore() {
    ops.add('restore');
    if (_stack.length > 1) {
      _stack.removeLast();
    }
  }

  @override
  void restoreToCount(int count) {
    ops.add('restoreToCount');
    while (_stack.length > count && _stack.length > 1) {
      _stack.removeLast();
    }
  }

  @override
  int getSaveCount() => _stack.length;

  @override
  void translate(double dx, double dy) {
    ops.add('translate');
    _stack.last.translate(dx, dy);
  }

  @override
  void scale(double sx, [double? sy]) {
    ops.add('scale');
    _stack.last.scale(sx, sy ?? sx);
  }

  @override
  void rotate(double radians) {
    ops.add('rotate');
    _stack.last.rotateRadians(radians);
  }

  @override
  void skew(double sx, double sy) {
    ops.add('skew');
    _stack.last.skew(sx, sy);
  }

  @override
  void transform(Float64List matrix4) {
    ops.add('transform');
    _stack.last.concatMatrix4(matrix4);
  }

  @override
  Float64List getTransform() => _stack.last.toMatrix4();

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    drawPaths.add(DrawPathCall(path, paint, _stack.last.clone()));
  }

  // -- Todo o resto é no-op para os testes. --

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}

  @override
  void clipRRect(ui.RRect rrect, {bool doAntiAlias = true}) {}

  @override
  void clipRSuperellipse(
    ui.RSuperellipse rsuperellipse, {
    bool doAntiAlias = true,
  }) {}

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {}

  @override
  ui.Rect getLocalClipBounds() => ui.Rect.zero;

  @override
  ui.Rect getDestinationClipBounds() => ui.Rect.zero;

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {}

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {}

  @override
  void drawPaint(ui.Paint paint) {}

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {}

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {}

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, ui.Paint paint) {}

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, ui.Paint paint) {}

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {}

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {}

  @override
  void drawArc(
    ui.Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    ui.Paint paint,
  ) {}

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {}

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) {}

  @override
  void drawImageNine(
    ui.Image image,
    ui.Rect center,
    ui.Rect dst,
    ui.Paint paint,
  ) {}

  @override
  void drawPicture(ui.Picture picture) {}

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    drawParagraphs.add(
      DrawParagraphCall(paragraph, offset, _stack.last.clone()),
    );
  }

  @override
  void drawPoints(
    ui.PointMode pointMode,
    List<ui.Offset> points,
    ui.Paint paint,
  ) {}

  @override
  void drawRawPoints(
    ui.PointMode pointMode,
    Float32List points,
    ui.Paint paint,
  ) {}

  @override
  void drawVertices(
    ui.Vertices vertices,
    ui.BlendMode blendMode,
    ui.Paint paint,
  ) {}

  @override
  void drawAtlas(
    ui.Image atlas,
    List<ui.RSTransform> transforms,
    List<ui.Rect> rects,
    List<ui.Color>? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {}

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {}

  @override
  void drawShadow(
    ui.Path path,
    ui.Color color,
    double elevation,
    bool transparentOccluder,
  ) {}
}

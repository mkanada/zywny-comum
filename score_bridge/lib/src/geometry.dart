// Geometria: `v`/`i`/`o` -> `ui.Path` (R02a).
//
// Implementa a conversão normativa da especificação
// (docs/formato/especificacao-v1.md §4.1) para formas `p` (e contornos de
// glifo), retângulos `r` e elipses `e`. Funções puras, sem `Canvas`.
//
// O laço quente ([pathFromBeziers]) percorre os `Float64List` planos sem
// criar `Offset` intermediários.
library;

import 'dart:ui' as ui;

import 'model.dart';

/// Converte subpaths de Bézier (`p` e glifos) em um `ui.Path` (§4.1).
///
/// ```text
/// moveTo(v[0])
/// para k de 0 até n-2:
///     cubicTo(v[k] + o[k], v[k+1] + i[k+1], v[k+1])
/// se closed:
///     cubicTo(v[n-1] + o[n-1], v[0] + i[0], v[0]); close()
/// ```
///
/// `v`/`i`/`o` são arrays planos de pares (x, y); `i`/`o` são tangentes
/// relativas ao vértice. Subpaths com menos de 1 vértice são ignorados; com
/// 1 vértice viram só um `moveTo` (mais `close` se fechado).
ui.Path pathFromBeziers(List<BezierPath> subpaths) {
  final path = ui.Path();
  for (final subpath in subpaths) {
    _addBezierSubpath(path, subpath);
  }
  return path;
}

void _addBezierSubpath(ui.Path path, BezierPath subpath) {
  final v = subpath.v;
  final i = subpath.i;
  final o = subpath.o;
  final n = v.length ~/ 2;
  if (n == 0) {
    return;
  }
  path.moveTo(v[0], v[1]);
  for (var k = 0; k < n - 1; k++) {
    final x0 = v[2 * k];
    final y0 = v[2 * k + 1];
    final x1 = v[2 * k + 2];
    final y1 = v[2 * k + 3];
    path.cubicTo(
      x0 + o[2 * k],
      y0 + o[2 * k + 1],
      x1 + i[2 * k + 2],
      y1 + i[2 * k + 3],
      x1,
      y1,
    );
  }
  if (subpath.closed) {
    final xLast = v[2 * (n - 1)];
    final yLast = v[2 * (n - 1) + 1];
    path.cubicTo(
      xLast + o[2 * (n - 1)],
      yLast + o[2 * (n - 1) + 1],
      v[0] + i[0],
      v[1] + i[1],
      v[0],
      v[1],
    );
    path.close();
  }
}

/// Converte um retângulo `r` (§5.2) em `ui.Path`.
///
/// `rx > 0` vira `RRect.fromRectXY` (o formato só carrega um raio).
ui.Path pathForRect(SceneRect r) {
  final rect = ui.Rect.fromLTWH(r.x, r.y, r.w, r.h);
  if (r.rx > 0) {
    return ui.Path()..addRRect(ui.RRect.fromRectXY(rect, r.rx, r.rx));
  }
  return ui.Path()..addRect(rect);
}

/// Converte uma elipse `e` (§5.2) em `ui.Path` via `addOval`.
ui.Path pathForEllipse(SceneEllipse e) {
  final rect = ui.Rect.fromCenter(
    center: ui.Offset(e.cx, e.cy),
    width: 2 * e.rx,
    height: 2 * e.ry,
  );
  return ui.Path()..addOval(rect);
}

// ---------------------------------------------------------------------------
// Cache por objeto, lazy (R02a §2).
// ---------------------------------------------------------------------------
//
// O modelo de R01 é imutável com construtores `const`; um campo `_cached`
// mutável obrigaria a remover o `const` de `ScenePath`/`SceneRect`/
// `SceneEllipse`/`GlyphDef`. Em vez disso o cache fica aqui, num `Expando`,
// e o modelo não muda: a mesma instância de modelo devolve sempre a mesma
// instância de `Path` (`identical`), sem custo de conversão por frame (A01).

final Expando<ui.Path> _pathCache = Expando<ui.Path>('R02a.pathCache');

ui.Path _cachedPath(Object key, ui.Path Function() build) {
  final cached = _pathCache[key];
  if (cached != null) {
    return cached;
  }
  final built = build();
  _pathCache[key] = built;
  return built;
}

/// Acesso `path` com cache para formas `p`.
extension ScenePathGeometry on ScenePath {
  ui.Path get path => _cachedPath(this, () => pathFromBeziers(paths));
}

/// Acesso `path` com cache para retângulos `r`.
extension SceneRectGeometry on SceneRect {
  ui.Path get path => _cachedPath(this, () => pathForRect(this));
}

/// Acesso `path` com cache para elipses `e`.
extension SceneEllipseGeometry on SceneEllipse {
  ui.Path get path => _cachedPath(this, () => pathForEllipse(this));
}

/// Contorno do glifo em unidades de fonte, sem transformação (R03b aplica a
/// escala de `u`).
extension GlyphDefGeometry on GlyphDef {
  ui.Path get path => _cachedPath(this, () => pathFromBeziers(paths));
}

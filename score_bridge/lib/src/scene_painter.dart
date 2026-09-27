// `ScenePainter`: ajuste de página, percurso da árvore e cor herdada (R02b),
// mais traço, opacidade, pontas/junções e tracejado (R02c), mais instâncias
// de glifo `u` (R03b) e runs de texto `t` (R04b/R04c).
//
// Desenha formas `p`/`r`/`e` com preenchimento e traço (§5.2/§6), usos de
// glifo `u` (§5.3) via `GlyphCache` (R03a) e texto comum (§5.4) via
// `painterForRun` (R04a/R04b) com os três alinhamentos (R04c).
//
// O percurso da árvore em si (ordem, `hidden`, cor herdada) vive em
// `scene_walk.dart` e é compartilhado com a segmentação (A01a); aqui só há o
// visitante que desenha.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dash.dart';
import 'geometry.dart';
import 'glyph_cache.dart';
import 'model.dart';
import 'scene_walk.dart';
import 'text_run.dart';

/// O preto opaco do `color="black"` do `<svg class="definition-scale">`: a
/// cor que a raiz de uma página herda (§6).
const kPageInitialColor = ui.Color(0xFF000000);

/// Fração do lado mais curto da `bbox` de um nó usada como raio do borrão do
/// halo ([ScenePainter.paintHalo]) — assim o halo acompanha o tamanho da nota
/// em vez de um valor fixo em unidades de viewBox.
const kHaloBlurFraction = 0.35;

/// Raio do borrão do halo quando o nó não traz `bbox`.
const kHaloBlurFallbackSigma = 24.0;

/// Pinta uma página da cena num [Canvas] (§3/§5.1/§6).
///
/// Aplica a transformação de página uma vez ([PageFit] + `origin` vindos
/// prontos do arquivo), percorre `children` em ordem de documento mantendo
/// a cor corrente por parâmetro, respeita `hidden` e `rotate`.
class ScenePainter {
  ScenePainter(
    this.page,
    Map<String, GlyphDef> glyphs, {
    this.colorOverrides = const {},
    GlyphCache? glyphCache,
  }) : glyphs = glyphs,
       _glyphCache = glyphCache ?? GlyphCache(glyphs);

  final ScenePage page;
  final Map<String, GlyphDef> glyphs;

  /// Contornos de glifo memoizados (R03a). Por defeito é construído a partir
  /// de [glyphs]; o chamador pode injetar o `document.glyphCache` para
  /// compartilhar entre páginas/painters.
  final GlyphCache _glyphCache;
  final Map<String, ui.Color> colorOverrides;

  /// Contornos memoizados compartilháveis (R03a). Expõe o cache injetado
  /// ou o interno para que o teste de contagem confira `builtCount`.
  GlyphCache get glyphCache => _glyphCache;

  // Reuso de `Paint` entre usos consecutivos com a mesma cor (R03b §4): uma
  // página do Nocturne tem 2 665 usos, alocar 2 `Paint` por uso é evitável.
  ui.Paint? _cachedGlyphFill;
  ui.Color? _cachedGlyphFillColor;
  ui.Paint? _cachedGlyphStroke;
  ui.Color? _cachedGlyphStrokeColor;
  double? _cachedGlyphStrokeWidth;
  SceneLineCap? _cachedGlyphStrokeCap;
  SceneLineJoin? _cachedGlyphStrokeJoin;

  void paint(ui.Canvas canvas) {
    applyPageTransform(canvas);
    // Pilha de cor começa em preto opaco: o `color="black"` do
    // `<svg class="definition-scale">` (§6). O percurso é o de `walkScene`,
    // o mesmo da segmentação (A01a).
    walkScene(
      page.root,
      kPageInitialColor,
      _CanvasVisitor(this, canvas),
      colorOverrides: colorOverrides,
    );
  }

  /// Aplica ao [canvas] a transformação de página (§3): `translate(fit)`,
  /// `scale` e `translate(origin)`. Depois dela o `Canvas` está no espaço de
  /// conteúdo, em unidades de viewBox — o espaço em que os segmentos de A01a
  /// e os `Picture` de A01b são gravados.
  void applyPageTransform(ui.Canvas canvas) {
    canvas.translate(page.fit.tx, page.fit.ty);
    canvas.scale(page.fit.scale);
    canvas.translate(page.origin.dx, page.origin.dy);
  }

  /// Pinta uma folha (forma, uso de glifo ou run de texto) com a cor herdada
  /// [color] já resolvida. É o que um segmento estático (A01a) chama, um item
  /// por vez, sem percurso de árvore.
  void paintLeaf(ui.Canvas canvas, SceneChild leaf, ui.Color color) =>
      _paintLeaf(canvas, leaf, color);

  /// Pinta o subgrafo de [node] como o percurso da página o faria, dado o
  /// estado herdado **antes** dele ([inheritedColor]). [overrides] troca a
  /// cor de qualquer nó do subgrafo por `id` (inclusive o próprio [node]) e
  /// vence o `color` do nó; não altera o [colorOverrides] do painter.
  ///
  /// O `rotate` dos ancestrais é do chamador (o `transform` do `DynamicItem`
  /// de A01a); o do próprio [node] é aplicado aqui.
  void paintSubtree(
    ui.Canvas canvas,
    SceneNode node,
    ui.Color inheritedColor, {
    Map<String, ui.Color> overrides = const {},
  }) {
    walkScene(
      node,
      inheritedColor,
      _CanvasVisitor(this, canvas),
      colorOverrides: overrides,
    );
  }

  /// Pinta o halo (A02d) do subgrafo de [node]: a mesma silhueta do destaque,
  /// numa camada borrada e **sem deslocamento**, sempre a [color] inteira
  /// (ignora `fill`/`stroke` por leaf — um halo é uma cor só). Chame **antes**
  /// de [paintSubtree] no mesmo [node], nunca depois, para a pintura nítida
  /// ficar por cima.
  ///
  /// [color] já traz o alfa da fase (attack/hold/release) — quem chama (o
  /// `PageLayers`) só entra aqui com um `id` que tem halo agora. O raio do
  /// borrão acompanha [SceneNode.bbox] do próprio nó, então funciona a
  /// qualquer `unit`/zoom sem parâmetro extra; sem bbox (raro), cai no
  /// [kHaloBlurFallbackSigma]. [sigmaScale] é o controle do usuário (painel):
  /// `1.0` é o tamanho acima, `0` desliga o halo sem custo de `saveLayer`.
  void paintHalo(
    ui.Canvas canvas,
    SceneNode node,
    ui.Color inheritedColor,
    ui.Color color, {
    double sigmaScale = 1.0,
  }) {
    if (sigmaScale <= 0) {
      return;
    }
    final bbox = node.bbox;
    final sigma =
        (bbox == null
            ? kHaloBlurFallbackSigma
            : math.min(bbox.width, bbox.height) * kHaloBlurFraction) *
        sigmaScale;
    canvas.saveLayer(
      null,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    walkScene(
      node,
      inheritedColor,
      _CanvasVisitor(this, canvas),
      colorOverrides: node.id == null ? const {} : {node.id!: color},
    );
    canvas.restore();
  }

  void _paintLeaf(ui.Canvas canvas, SceneChild leaf, ui.Color current) {
    switch (leaf) {
      case SceneNode():
        // Grupos são tratados por `walkScene`; nunca chegam como folha.
        return;
      case ScenePath():
        _drawShape(canvas, leaf, leaf.path, current);
      case SceneRect():
        _drawShape(canvas, leaf, leaf.path, current);
      case SceneEllipse():
        _drawShape(canvas, leaf, leaf.path, current);
      case SceneGlyphUse():
        _drawGlyphUse(canvas, leaf, current);
      case SceneText():
        _drawText(canvas, leaf, current);
    }
  }

  /// Pinta uma forma `p`/`r`/`e`: preenchimento primeiro, traço depois (é a
  /// ordem do SVG), com duas `Paint` separadas (§5.2).
  ///
  /// `strokeWidth` ausente vira `1.0` (padrão IR para `p`/`r`/`e`; no corpus
  /// atual o campo nunca falta). O caminho do traço leva o tracejado quando
  /// `dash` está presente; o do preenchimento nunca (semântica do SVG:
  /// `stroke-dasharray` só afeta o traço). `strokeWidth` fica em unidades de
  /// viewBox: a escala da página é do `Canvas`, nunca da `Paint`.
  void _drawShape(
    ui.Canvas canvas,
    SceneShape shape,
    ui.Path basePath,
    ui.Color current,
  ) {
    final fill = _resolveChannelColor(shape.fill, current, shape.fillOpacity);
    if (fill != null) {
      canvas.drawPath(
        basePath,
        ui.Paint()
          ..color = fill
          ..style = ui.PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }
    final stroke = _resolveChannelColor(
      shape.stroke,
      current,
      shape.strokeOpacity,
    );
    if (stroke != null) {
      final strokePath = shape.dash == null
          ? basePath
          : applyDash(basePath, shape.dash!);
      canvas.drawPath(
        strokePath,
        ui.Paint()
          ..color = stroke
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth ?? 1.0
          ..strokeCap = _toStrokeCap(shape.lineCap)
          ..strokeJoin = _toStrokeJoin(shape.lineJoin)
          ..isAntiAlias = true,
      );
    }
  }

  /// Pinta um uso de glifo `u` (§5.3, R03b): o mesmo `ui.Path` do dicionário
  /// sob `translate(x, y) scale(sx, sy)`, preenchido **e** traçado com a cor
  /// herdada (é o `<use>` de `DrawMusicText` em `svgdevicecontext.cpp`).
  ///
  /// O `<path>` referenciado cai sob a regra CSS global
  /// `ellipse, path, ... {stroke:currentColor}`: sem o traço os glifos saem
  /// visivelmente mais finos (divergência de alguns por cento no diff).
  /// `strokeWidth: 1.0` **dentro** do `save/scale` equivale a `sy` em
  /// unidades de viewBox — que é exatamente o que §5.3 documenta. Não fazer
  /// a conta à mão fora do `scale`: é a mesma coisa e uma fonte a menos
  /// de erro.
  ///
  /// Quando `strokeWidth` explícito está presente (nunca no corpus), o valor
  /// vem em unidades de viewBox e é convertido para o espaço do glifo com
  /// `strokeWidth / sy` antes de usar dentro do `scale`.
  /// `dash` em `u` não tem ocorrência no corpus e é ignorado aqui.
  void _drawGlyphUse(ui.Canvas canvas, SceneGlyphUse use, ui.Color current) {
    final glyphPath = _glyphCache.pathFor(use.glyphId);
    final fill = _resolveChannelColor(use.fill, current, use.fillOpacity);
    final stroke = _resolveChannelColor(use.stroke, current, use.strokeOpacity);
    if (fill == null && stroke == null) {
      return;
    }
    canvas.save();
    canvas.translate(use.x, use.y);
    // `sx` e `sy` separados: iguais em todo o corpus, mas o formato permite
    // diferirem (`widthToHeightRatio`).
    canvas.scale(use.sx, use.sy);
    if (fill != null) {
      canvas.drawPath(glyphPath, _glyphFillPaint(fill));
    }
    if (stroke != null) {
      final double widthInGlyphSpace = use.strokeWidth == null
          ? 1.0
          : use.strokeWidth! / use.sy;
      canvas.drawPath(
        glyphPath,
        _glyphStrokePaint(stroke, widthInGlyphSpace, use.lineCap, use.lineJoin),
      );
    }
    canvas.restore();
  }

  /// `Paint` de preenchimento de glifo com reuso entre usos consecutivos da
  /// mesma cor final (R03b §4).
  ui.Paint _glyphFillPaint(ui.Color color) {
    final cached = _cachedGlyphFill;
    if (cached != null && _cachedGlyphFillColor == color) {
      return cached;
    }
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = true;
    _cachedGlyphFill = paint;
    _cachedGlyphFillColor = color;
    return paint;
  }

  /// `Paint` de traço de glifo com reuso por (cor, largura, cap, join).
  ui.Paint _glyphStrokePaint(
    ui.Color color,
    double widthInGlyphSpace,
    SceneLineCap cap,
    SceneLineJoin join,
  ) {
    final cached = _cachedGlyphStroke;
    if (cached != null &&
        _cachedGlyphStrokeColor == color &&
        _cachedGlyphStrokeWidth == widthInGlyphSpace &&
        _cachedGlyphStrokeCap == cap &&
        _cachedGlyphStrokeJoin == join) {
      return cached;
    }
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = widthInGlyphSpace
      ..strokeCap = _toStrokeCap(cap)
      ..strokeJoin = _toStrokeJoin(join)
      ..isAntiAlias = true;
    _cachedGlyphStroke = paint;
    _cachedGlyphStrokeColor = color;
    _cachedGlyphStrokeWidth = widthInGlyphSpace;
    _cachedGlyphStrokeCap = cap;
    _cachedGlyphStrokeJoin = join;
    return paint;
  }

  /// Pinta um run de texto comum `t` (§5.4, R04b/R04c).
  ///
  /// `x`/`y` do formato são a âncora da **linha de base** (como no SVG:
  /// `StartText`/`MoveTextTo`); o `TextPainter` pinta a partir do **topo**,
  /// daí `run.y - dy`. O deslocamento horizontal reproduz `text-anchor`:
  /// `left` (=`start`) ancora em `x`, `center` (=`middle`) centra a largura
  /// medida sobre `x`, `right` (=`end`) termina em `x`. `painter.width` já
  /// inclui o `letterSpacing` final (sondado em R04c), como o `resvg`.
  void _drawText(ui.Canvas canvas, SceneText run, ui.Color current) {
    final color = run.color == null ? current : parseCssColor(run.color!);
    final painter = painterForRun(run, color);
    final dy = painter.computeDistanceToActualBaseline(
      ui.TextBaseline.alphabetic,
    );
    // `width` exige `layout()` prévio (`painterForRun` já fez); sem ele
    // seria 0 e tudo alinharia à esquerda silenciosamente.
    final dx = switch (run.align) {
      SceneTextAlign.left => 0.0,
      SceneTextAlign.center => -painter.width / 2,
      SceneTextAlign.right => -painter.width,
    };
    painter.paint(canvas, ui.Offset(run.x + dx, run.y - dy));
  }
}

/// Visitante que pinta o percurso de [walkScene] num [ui.Canvas]: `rotate`
/// vira `save/translate/rotate/translate` na entrada e `restore` na saída.
class _CanvasVisitor implements SceneVisitor {
  _CanvasVisitor(this._painter, this._canvas);

  final ScenePainter _painter;
  final ui.Canvas _canvas;

  @override
  bool enterGroup(SceneNode node, ui.Color inheritedColor, ui.Color color) {
    final r = node.rotate;
    if (r != null) {
      _canvas.save();
      _canvas.translate(r.origin.dx, r.origin.dy);
      _canvas.rotate(r.angle * math.pi / 180.0);
      _canvas.translate(-r.origin.dx, -r.origin.dy);
    }
    return true;
  }

  @override
  void visitLeaf(SceneChild leaf, ui.Color color) =>
      _painter._paintLeaf(_canvas, leaf, color);

  @override
  void exitGroup(SceneNode node) {
    if (node.rotate != null) {
      _canvas.restore();
    }
  }
}

/// Resolve a cor de um canal (`fill`/`stroke`): `none` vira `null` (não
/// pinta), `inherit` usa a cor corrente, cor explícita usa o hex. O alfa
/// final é `alfaDaCor × opacity`, com arredondamento metade para cima na
/// hora de quantizar para 8 bits (`0.5 sobre #ff0000` dá alfa 128: 127.5
/// arredonda para cima).
ui.Color? _resolveChannelColor(
  ScenePaint paint,
  ui.Color current,
  double opacity,
) {
  if (identical(paint, ScenePaint.none)) {
    return null;
  }
  final ui.Color base = paint is ColorPaint
      ? parseCssColor(paint.hex)
      : current;
  if (opacity >= 1.0) {
    return base;
  }
  return base.withValues(alpha: (base.a * opacity).clamp(0.0, 1.0));
}

/// `default` = "o exportador não pediu nada" → default do SVG quando o
/// atributo está ausente (`butt`, é o que o `resvg` aplica).
ui.StrokeCap _toStrokeCap(SceneLineCap cap) {
  switch (cap) {
    case SceneLineCap.defaultCap:
      return ui.StrokeCap.butt;
    case SceneLineCap.butt:
      return ui.StrokeCap.butt;
    case SceneLineCap.round:
      return ui.StrokeCap.round;
    case SceneLineCap.square:
      return ui.StrokeCap.square;
  }
}

/// `default` → `miter` (default do SVG). `arcs` e `miter-clip` não existem no
/// Flutter e são mapeados para `miter`; nenhum dos dois ocorre no corpus
/// (só `default`/`round`/`miter`/`bevel` aparecem nas formas — e `arcs`/
/// `miter-clip` em zero ocorrências).
ui.StrokeJoin _toStrokeJoin(SceneLineJoin join) {
  switch (join) {
    case SceneLineJoin.defaultJoin:
      return ui.StrokeJoin.miter;
    case SceneLineJoin.arcs:
      return ui.StrokeJoin.miter;
    case SceneLineJoin.bevel:
      return ui.StrokeJoin.bevel;
    case SceneLineJoin.miter:
      return ui.StrokeJoin.miter;
    case SceneLineJoin.miterClip:
      return ui.StrokeJoin.miter;
    case SceneLineJoin.round:
      return ui.StrokeJoin.round;
  }
}

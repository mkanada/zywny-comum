// `ScorePageView`: uma página da partitura como widget de produção (A01b).
//
// Camadas: os segmentos estáticos de A01a viram `ui.Picture` gravados uma vez
// (ver `PageLayers`) e os dinâmicos são pintados ao vivo com as cores do
// `ScoreCubit`. `RepaintBoundary` em volta do `CustomPaint`, e o `repaint:` do
// painter ligado aos cubits (por um `BlocRepaint`): uma mudança de cor repinta
// sem `setState`, sem reconstruir widget e sem refazer layout.
//
// ESTADO (BL26): as camadas, os ids promovidos e as folhas escondidas são do
// [ScorePageCubit], que esta página põe em volta de si (um `BlocProvider`). O
// cubit vive enquanto a página viver na árvore (a `GlobalKey` do `ScoreView` a
// mantém), e a cada build a página passa a ele os seus parâmetros (`sync`). Este
// widget não tem estado: o pintor lê as camadas do cubit ao pintar.
//
// TAMANHO: o widget tem a proporção da página (`widthPx : heightPx`) e escala
// o desenho para ocupar a largura que recebe. Os `Picture` são gravados em
// unidades de viewBox, então redimensionar não recompila nada.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'band.dart';
import 'ghost_layer.dart';
import 'hit_test.dart';
import 'model.dart';
import 'page_layers.dart';
import 'score_cubit.dart';
import 'score_page_cubit.dart';
import 'stand_in_layer.dart';

class ScorePageView extends StatelessWidget {
  const ScorePageView({
    super.key,
    required this.document,
    required this.pageIndex,
    this.sequence,
    this.controller,
    this.animatableIds,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.haloSigmaScale = 1.0,
    this.stats,
    this.overlayIds = const [],
    this.overlayBuilder,
    this.overlayUniformHeight = false,
    this.onElementTap,
    this.tapClasses,
    this.ghosts,
    this.standIns,
    this.bands,
  });

  final VsbDocument document;
  final int pageIndex;

  /// `null` (padrão) = página normal (`PageRef(pageIndex)`). Um índice de
  /// sequência mostra `PageRef(pageIndex, sequence: sequence)` — uma página
  /// alternativa (§2.5, P03b) — com os mesmos ids de nota/compasso das
  /// páginas normais, então cor e destaque (`ScoreCubit`) acendem sem
  /// código novo.
  final int? sequence;

  /// Cor por id e destaques. Sem controller a página só mostra o repouso.
  final ScoreCubit? controller;

  /// Ids que podem mudar de cor sem recompilar a página. `null` é o padrão:
  /// os ids `on`/`off` do timemap do documento (vazio, se não há timemap).
  /// Um id que o controller colore e que não está aqui é promovido a
  /// dinâmico, ao custo de recompilar os `Picture` da página.
  final Set<String>? animatableIds;

  /// Fundo da página; `null` deixa transparente.
  final Color? backgroundColor;

  /// Controle do usuário sobre a largura do halo (A02d): `1.0` é o tamanho
  /// derivado da nota, `0` desliga. Ver [ScenePainter.paintHalo].
  final double haloSigmaScale;

  /// Ids que viram widgets de verdade (A04b), um `Positioned` por id sobre a
  /// bbox dele. O padrão é vazio — **custo zero**: a árvore fica idêntica
  /// à de antes dos overlays. Ids que não estão nesta página são ignorados.
  ///
  /// O overlay é uma camada de widget **acima** de toda a partitura: não
  /// participa da ordem de pintura da cena, e vive dentro da página, então é
  /// recortado junto com ela na virada por haste (A03b).
  final Iterable<String> overlayIds;

  /// Constrói o widget de [id]; [rect] é a bbox em pixels lógicos da página
  /// (a origem é o canto dela). Devolver `null` omite o overlay. É chamado a
  /// cada layout — nada de posição memorizada.
  final Widget? Function(BuildContext context, String id, Rect rect)?
  overlayBuilder;

  /// Iguala a altura dos overlays que estão no mesmo sistema (mesma linha
  /// da página): cada um ocupa do topo mais alto à base mais baixa do grupo.
  /// Para fundos de compasso, que senão seguem a bbox de cada um.
  final bool overlayUniformHeight;

  /// Toque num elemento: recebe o id mais específico (menor bbox) sob o
  /// toque, filtrado por [tapClasses]; não dispara em área vazia. Um único
  /// detector para a página inteira. Para tocar a partir dali, ligue a um
  /// `ScorePlayer` (E02c): `onElementTap: (id) => player.seekToElement(id)`.
  final void Function(String id)? onElementTap;

  /// Classes que [onElementTap] aceita; `null` é `{'note'}`.
  final Set<String>? tapClasses;

  /// Fantasmas de teclas erradas (G05), pintadas por cima da página com o
  /// mesmo transform dela. `null` (padrão): nenhuma camada extra.
  final GhostCubit? ghosts;

  /// Pausas substitutas das colunas escondidas (L03), pintadas por cima da
  /// página com o mesmo transform dela (e por baixo das fantasmas). `null`
  /// (padrão): nenhuma camada extra, custo zero.
  final StandInCubit? standIns;

  /// Faixas atrás das notas (LP03): o aluno em azul, com o aviso. `null` não
  /// desenha nenhuma.
  final ScoreBandCubit? bands;

  /// Contadores de `Picture` a usar. Um dono que monta várias páginas (o
  /// `ScoreView`) passa o mesmo objeto a todas para somar a vida útil delas;
  /// sem ele a página tem os seus.
  final PictureStats? stats;

  @override
  Widget build(BuildContext context) => BlocProvider<ScorePageCubit>(
    create: (_) => ScorePageCubit(
      document: document,
      pageIndex: pageIndex,
      sequence: sequence,
      controller: controller,
      animatableIds: animatableIds,
      stats: stats,
    ),
    child: Builder(builder: _paint),
  );

  Widget _paint(BuildContext context) {
    final cubit = context.read<ScorePageCubit>();
    cubit.sync(
      document: document,
      pageIndex: pageIndex,
      sequence: sequence,
      controller: controller,
      animatableIds: animatableIds,
    );
    final page = cubit.page;
    // Os cubits de faixa e de fantasma guardam o documento para achar as notas
    // (é idempotente: outro documento refaz o que eles têm).
    ghosts?.attachDocument(document);
    standIns?.attachDocument(document);
    final Widget baseLayer = RepaintBoundary(
      child: CustomPaint(
        painter: _PagePainter(
          cubit,
          controller,
          backgroundColor,
          haloSigmaScale,
          bands: bands,
          pageIndex: pageIndex,
          geometry: document.geometryOf(sequence),
        ),
      ),
    );
    Widget base = baseLayer;
    final ghostCubit = ghosts;
    final standInCubit = standIns;
    if (ghostCubit != null || standInCubit != null) {
      final pageRef = PageRef(pageIndex, sequence: sequence);
      void applyTransform(ui.Canvas canvas) =>
          cubit.layers.applyPageTransform(canvas);
      base = Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.passthrough,
        children: [
          baseLayer,
          if (standInCubit != null)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: StandInPainter(
                    controller: standInCubit,
                    page: page,
                    pageRef: pageRef,
                    glyphCache: document.glyphCache,
                    applyPageTransform: applyTransform,
                  ),
                ),
              ),
            ),
          if (ghostCubit != null)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: GhostPainter(
                    controller: ghostCubit,
                    page: page,
                    pageRef: pageRef,
                    glyphCache: document.glyphCache,
                    applyPageTransform: applyTransform,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final hasOverlay = overlayBuilder != null && overlayIds.isNotEmpty;
    return AspectRatio(
      aspectRatio: page.widthPx / page.heightPx,
      child: hasOverlay || onElementTap != null
          ? LayoutBuilder(
              builder: (context, constraints) =>
                  _withInteraction(context, constraints.maxWidth, base),
            )
          : base,
    );
  }

  /// Camadas de widget por cima da página (A04b): overlays por id e o
  /// detector de toque. Só existe se o host pediu.
  Widget _withInteraction(BuildContext context, double width, Widget base) {
    final geometry = document.geometryOf(sequence);
    final builder = overlayBuilder;
    Widget result = base;
    if (builder != null && overlayIds.isNotEmpty) {
      final children = <Widget>[base];
      final rects = <String, Rect>{};
      for (final id in overlayIds) {
        final ref = geometry.elementOf(id);
        if (ref == null || ref.page != pageIndex) {
          continue;
        }
        rects[id] = geometry.rectOf(ref, pageWidth: width);
      }
      if (overlayUniformHeight) _unifySystemHeights(rects);
      for (final entry in rects.entries) {
        final id = entry.key;
        final rect = entry.value;
        final child = builder(context, id, rect);
        if (child != null) {
          children.add(
            Positioned.fromRect(
              key: ValueKey<String>('overlay:$id'),
              rect: rect,
              child: child,
            ),
          );
        }
      }
      result = Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.passthrough,
        children: children,
      );
    }
    final tap = onElementTap;
    if (tap != null) {
      final classes = tapClasses ?? const {'note'};
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final id = geometry.idAt(
            pageIndex,
            details.localPosition,
            pageWidth: width,
            classes: classes,
          );
          // Nota escondida não responde a toque: transparente não é ausente.
          if (id != null && !(controller?.isHidden(id) ?? false)) {
            tap(id);
          }
        },
        child: result,
      );
    }
    return result;
  }
}

/// Agrupa os retângulos que se sobrepõem na vertical (um sistema) e estica
/// cada um até o topo e a base do grupo.
void _unifySystemHeights(Map<String, Rect> rects) {
  final sorted = rects.entries.toList()
    ..sort((a, b) => a.value.top.compareTo(b.value.top));
  var group = <MapEntry<String, Rect>>[];
  var bottom = double.negativeInfinity;
  void flush() {
    if (group.isEmpty) return;
    final top = group.map((e) => e.value.top).reduce(math.min);
    final bot = group.map((e) => e.value.bottom).reduce(math.max);
    for (final e in group) {
      rects[e.key] = Rect.fromLTRB(e.value.left, top, e.value.right, bot);
    }
    group = [];
  }

  for (final e in sorted) {
    if (group.isNotEmpty && e.value.top > bottom) {
      flush();
      bottom = double.negativeInfinity;
    }
    group.add(e);
    bottom = math.max(bottom, e.value.bottom);
  }
  flush();
}

/// O que o `Listenable` do painter escuta: um `BlocRepaint` da página (as camadas
/// refeitas), o do cubit de cores e o de faixas (os que existirem). O painter lê
/// as camadas, o mapa e as faixas ao pintar; o `BlocRepaint` só avisa que vale
/// repintar.
Listenable _repaintOf(
  ScorePageCubit page,
  ScoreCubit? colors,
  ScoreBandCubit? bands,
) {
  final list = <Listenable>[
    BlocRepaint(page),
    if (colors != null) BlocRepaint(colors),
    if (bands != null) BlocRepaint(bands),
  ];
  return list.length == 1 ? list.single : Listenable.merge(list);
}

class _PagePainter extends CustomPainter {
  /// As camadas da página são as do cubit; o pintor as lê ao pintar. [layers] é
  /// as do momento do build: se mudarem, a página nova repinta.
  _PagePainter(
    this.cubit,
    this.controller,
    this.backgroundColor,
    this.haloSigmaScale, {
    this.bands,
    required this.pageIndex,
    required this.geometry,
  }) : layers = cubit.layers,
       super(repaint: _repaintOf(cubit, controller, bands));

  final ScorePageCubit cubit;
  final PageLayers layers;
  final ScoreCubit? controller;
  final Color? backgroundColor;
  final double haloSigmaScale;

  /// As faixas atrás das notas (LP03); `null` não desenha nenhuma.
  final ScoreBandCubit? bands;
  final int pageIndex;
  final ScoreGeometry geometry;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final current = cubit.layers;
    final page = current.page;
    if (backgroundColor != null) {
      canvas.drawRect(
        ui.Offset.zero & size,
        ui.Paint()..color = backgroundColor!,
      );
    }
    final scale = size.width / page.widthPx;
    canvas.save();
    if (scale != 1.0) {
      canvas.scale(scale);
    }
    current.applyPageTransform(canvas);
    // A faixa vai depois do fundo e antes das notas: por baixo do halo e das
    // notas escondidas. As bbox da geometria estão no mesmo espaço de conteúdo
    // em que o `applyPageTransform` acabou de pôr o canvas.
    final b = bands;
    if (b != null && b.bands.isNotEmpty) {
      paintScoreBands(
        canvas,
        scoreBandRects(page, pageIndex, geometry, b.bands),
        fill: b.fill,
        labelColor: b.labelColor,
      );
    }
    current.paint(
      canvas,
      controller?.colors ?? const {},
      haloColors: controller?.haloColors ?? const {},
      haloSigmaScale: haloSigmaScale,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PagePainter oldDelegate) =>
      !identical(oldDelegate.layers, layers) ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.haloSigmaScale != haloSigmaScale ||
      !identical(oldDelegate.bands, bands);
}

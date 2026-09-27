// `ScorePageView`: uma página da partitura como widget de produção (A01b).
//
// Camadas: os segmentos estáticos de A01a viram `ui.Picture` gravados uma vez
// (ver `PageLayers`) e os dinâmicos são pintados ao vivo com as cores do
// `ScoreController`. `RepaintBoundary` em volta do `CustomPaint`, e o
// `repaint:` do painter ligado ao controller: uma mudança de cor repinta sem
// `setState`, sem reconstruir widget e sem refazer layout.
//
// TAMANHO: o widget tem a proporção da página (`widthPx : heightPx`) e escala
// o desenho para ocupar a largura que recebe. Os `Picture` são gravados em
// unidades de viewBox, então redimensionar não recompila nada.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'model.dart';
import 'page_layers.dart';
import 'score_controller.dart';
import 'segmentation.dart';

class ScorePageView extends StatefulWidget {
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
    this.onElementTap,
    this.tapClasses,
  });

  final VsbDocument document;
  final int pageIndex;

  /// `null` (padrão) = página normal (`PageRef(pageIndex)`). Um índice de
  /// sequência mostra `PageRef(pageIndex, sequence: sequence)` — uma página
  /// alternativa (§2.5, P03b) — com os mesmos ids de nota/compasso das
  /// páginas normais, então cor e destaque (`ScoreController`) acendem sem
  /// código novo.
  final int? sequence;

  /// Cor por id e destaques. Sem controller a página só mostra o repouso.
  final ScoreController? controller;

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

  /// Contadores de `Picture` a usar. Um dono que monta várias páginas (o
  /// `ScoreView`) passa o mesmo objeto a todas para somar a vida útil delas;
  /// sem ele a página tem os seus.
  final PictureStats? stats;

  /// Ids que viram widgets de verdade (A04b), um `Positioned` por id sobre a
  /// bbox dele. O padrão é vazio — **custo zero**: a árvore fica idêntica à
  /// de antes dos overlays. Ids que não estão nesta página são ignorados.
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

  /// Toque num elemento: recebe o id mais específico (menor bbox) sob o
  /// toque, filtrado por [tapClasses]; não dispara em área vazia. Um único
  /// detector para a página inteira. Para tocar a partir dali, ligue a um
  /// `ScorePlayer` (E02c): `onElementTap: (id) => player.seekToElement(id)`.
  final void Function(String id)? onElementTap;

  /// Classes que [onElementTap] aceita; `null` é `{'note'}`.
  final Set<String>? tapClasses;

  @override
  State<ScorePageView> createState() => ScorePageViewState();
}

class ScorePageViewState extends State<ScorePageView> {
  late final PictureStats _stats = widget.stats ?? PictureStats();
  PageLayers? _layers;
  Set<String> _animatableIds = const {};

  // Ids promovidos a dinâmicos porque o controller os colore (ver
  // `_collectPromotions`); zerado quando muda documento/página.
  final Set<String> _promoted = {};

  ScenePage get _page => widget.document.pageAt(
    PageRef(widget.pageIndex, sequence: widget.sequence),
  );

  @override
  void initState() {
    super.initState();
    widget.controller?.attachDocument(widget.document);
    widget.controller?.addListener(_onControllerChanged);
    _collectPromotions();
    _rebuildLayers();
  }

  @override
  void didUpdateWidget(ScorePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = widget.controller;
    if (oldWidget.controller != controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      controller?.addListener(_onControllerChanged);
    }
    controller?.attachDocument(widget.document);
    final structural =
        oldWidget.document != widget.document ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.sequence != widget.sequence ||
        !setEquals(oldWidget.animatableIds, widget.animatableIds);
    if (structural) {
      _promoted.clear();
    }
    if (structural || _collectPromotions()) {
      _rebuildLayers();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _layers?.dispose();
    super.dispose();
  }

  /// Recria as camadas: a única situação em que os `Picture` são recompilados
  /// (documento, página ou conjunto de ids dinâmicos mudou — nunca cor).
  void _rebuildLayers() {
    final old = _layers;
    _animatableIds = {
      ...(widget.animatableIds ??
          animatableIdsFromTimemap(
            widget.document.timemap,
            document: widget.document,
          )),
      ..._promoted,
    };
    _layers = PageLayers(
      _page,
      widget.document.glyphs,
      animatableIds: _animatableIds,
      glyphCache: widget.document.glyphCache,
      stats: _stats,
    );
    old?.dispose();
  }

  void _onControllerChanged() {
    if (_collectPromotions()) {
      setState(_rebuildLayers);
    }
  }

  /// Se o controller tem cor para um id que existe nesta página mas está num
  /// `Picture` estático, marca o id para promoção a dinâmico. Devolve se
  /// houve promoção nova (e as camadas precisam ser recriadas).
  bool _collectPromotions() {
    final controller = widget.controller;
    if (controller == null || controller.colors.isEmpty) {
      return false;
    }
    final byId = _page.byId;
    var added = false;
    for (final id in controller.colors.keys) {
      if (!_animatableIds.contains(id) &&
          !_promoted.contains(id) &&
          byId.containsKey(id)) {
        _promoted.add(id);
        added = true;
      }
    }
    return added;
  }

  /// Quantos `Picture` estáticos já foram gravados por este widget (todas as
  /// gerações de cache somadas). Não muda quando uma cor muda.
  @visibleForTesting
  int get pictureBuilds => _stats.builds;

  /// Quantos `Picture` estáticos já foram descartados.
  @visibleForTesting
  int get pictureDisposals => _stats.disposals;

  @visibleForTesting
  PictureStats get pictureStats => _stats;

  @visibleForTesting
  PageLayers get layers => _layers!;

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final Widget base = RepaintBoundary(
      child: CustomPaint(
        painter: _PagePainter(
          _layers!,
          widget.controller,
          widget.backgroundColor,
          widget.haloSigmaScale,
        ),
      ),
    );
    final hasOverlay =
        widget.overlayBuilder != null && widget.overlayIds.isNotEmpty;
    return AspectRatio(
      aspectRatio: page.widthPx / page.heightPx,
      child: hasOverlay || widget.onElementTap != null
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
    final geometry = widget.document.geometryOf(widget.sequence);
    final builder = widget.overlayBuilder;
    Widget result = base;
    if (builder != null && widget.overlayIds.isNotEmpty) {
      final children = <Widget>[base];
      for (final id in widget.overlayIds) {
        final ref = geometry.elementOf(id);
        if (ref == null || ref.page != widget.pageIndex) {
          continue;
        }
        final rect = geometry.rectOf(ref, pageWidth: width);
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
    final onTap = widget.onElementTap;
    if (onTap != null) {
      final classes = widget.tapClasses ?? const {'note'};
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final id = geometry.idAt(
            widget.pageIndex,
            details.localPosition,
            pageWidth: width,
            classes: classes,
          );
          if (id != null) {
            onTap(id);
          }
        },
        child: result,
      );
    }
    return result;
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(
    this.layers,
    this.controller,
    this.backgroundColor,
    this.haloSigmaScale,
  ) : super(repaint: controller);

  final PageLayers layers;
  final ScoreController? controller;
  final Color? backgroundColor;
  final double haloSigmaScale;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final page = layers.page;
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
    layers.applyPageTransform(canvas);
    layers.paint(
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
      oldDelegate.haloSigmaScale != haloSigmaScale;
}

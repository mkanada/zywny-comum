// `ScoreView`: a partitura inteira — trilha de páginas, virada por haste,
// rolagem contínua e navegação por elemento (A03a/A03b/A03c).
//
// TRÊS MODOS ([ScorePageMode]):
//   * `pagedSweep` (padrão): uma página por vez; a virada é a **haste** de
//     A03b — a página atual (A) e a seguinte (B) ficam uma sobre a outra e uma
//     faixa azul varre A da esquerda para a direita, revelando B.
//   * `pagedSlide`: a trilha horizontal; a virada é uma translação só, sem
//     haste.
//   * `continuousScroll`: páginas empilhadas numa lista virtualizada.
//
// REPOUSO PIXEL-IDÊNTICO: sem virada em curso a árvore contém **só** a página
// atual, centrada e em escala exata — nada de `ClipRect`, haste, `Transform`
// ou página vizinha. O recorte, a haste e a página B só existem enquanto a
// `edgeX` está estritamente dentro do intervalo aberto `(0, fim)`; e cada
// `ScorePageView` mora sob uma `GlobalKey`, de modo que aparecer/sumir o
// recorte não recompila o cache de `Picture`.
//
// COORDENADAS: `edgeX` está em unidades de viewBox da página A (o referencial
// de conteúdo do formato, o mesmo de `ElementRef.bbox`); a conversão para
// tela é a de `hit_test.dart` — uma fórmula só.
//
// QUEM MANDA NA HASTE: um `SweepCurtain` externo (`curtain:`, o player de
// A05b) tem a última palavra enquanto for não-nulo e estiver no intervalo; sem
// ele, `sweepTo`/`finishSweep`/`nextPage` animam a própria. A página atual
// acompanha `SweepCurtain.pageIndex`.
//
// INTERRUPÇÕES (definidas em A03b, testadas em `score_view_test.dart`):
//   * `goToPage`, `previousPage`: cancelam a virada em curso e vão direto ao
//     repouso da página de destino (instantâneos — `previousPage` **nunca**
//     usa a haste);
//   * `nextPage` durante uma varredura em curso: **conclui** a varredura (vai
//     ao fim), sem reiniciar;
//   * `curtain` externo que volta a `null`: o repouso da página corrente;
//   * na última página não há haste nem página de trás; `nextPage` satura.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

import 'hit_test.dart';
import 'model.dart';
import 'page_layers.dart';
import 'score_controller.dart';
import 'score_page_view.dart';
import 'scene_walk.dart';

enum ScorePageMode { pagedSweep, pagedSlide, continuousScroll }

/// Teto padrão da duração de cada movimento da haste.
const kDefaultMaxSweepDuration = Duration(seconds: 1);

/// Azul de alto contraste sobre papel branco (padrão de [ScoreView.barColor]).
const kDefaultBarColor = Color(0xFF1565C0);

/// Estado da haste, sempre derivado de fora (A05b/E03a): o widget só obedece.
@immutable
class SweepCurtain {
  const SweepCurtain({
    required this.pageIndex,
    required this.edgeX,
    this.sequence,
    this.targetPageIndex,
    this.targetSequence,
  });

  /// A página A, a que está sendo varrida (dentro de [sequence]).
  final int pageIndex;

  /// Borda **direita** da haste, em unidades de viewBox da página A.
  final double edgeX;

  /// Sequência alternativa de [pageIndex] (§2.5, P03b); `null` é página
  /// normal.
  final int? sequence;

  /// A página que a haste revela, atrás de A. `null` é a virada comum,
  /// `pageIndex + 1` **dentro da mesma sequência de [page]** (A05b); um
  /// salto de repetição (E03a) usa a página de destino, que pode vir antes,
  /// na mesma, ou bem depois de A — em qualquer sequência ([targetSequence]).
  final int? targetPageIndex;

  /// Sequência alternativa do destino; só importa quando [targetPageIndex]
  /// não é `null` (sem ele, o destino já está implícito na mesma sequência
  /// de [page] — ver [target]). `null` é página normal.
  final int? targetSequence;

  /// A página A como [PageRef].
  PageRef get page => PageRef(pageIndex, sequence: sequence);

  /// O destino como [PageRef]: sem [targetPageIndex], `pageIndex + 1` **na
  /// mesma sequência da frente**; com ele, [targetPageIndex] em
  /// [targetSequence] (página normal se omitido).
  PageRef get target => targetPageIndex == null
      ? PageRef(pageIndex + 1, sequence: sequence)
      : PageRef(targetPageIndex!, sequence: targetSequence);

  @override
  bool operator ==(Object other) =>
      other is SweepCurtain &&
      other.pageIndex == pageIndex &&
      other.edgeX == edgeX &&
      other.sequence == sequence &&
      other.targetPageIndex == targetPageIndex &&
      other.targetSequence == targetSequence;

  @override
  int get hashCode =>
      Object.hash(pageIndex, edgeX, sequence, targetPageIndex, targetSequence);

  @override
  String toString() =>
      'SweepCurtain(page: $page, edgeX: $edgeX, target: $target)';
}

/// Largura padrão da haste: `2 ×` a largura da cabeça de nota preta
/// (`noteheadBlack`, U+E0A4), em unidades de viewBox — a bbox do glifo vezes
/// a escala `sx` de uma ocorrência dele na cena. Sem nenhuma cabeça de nota
/// no documento, cai para [fallback].
double defaultBarWidth(VsbDocument document, {double fallback = 300}) {
  String? glyphId;
  for (final e in document.glyphs.entries) {
    if (e.value.codepoint.toUpperCase() == 'E0A4') {
      glyphId = e.key;
      break;
    }
  }
  if (glyphId == null) {
    return fallback;
  }
  final width = document.glyphs[glyphId]!.bbox.toContourRect().width;
  final finder = _FirstUse(glyphId);
  for (final page in document.pages) {
    walkScene(page.root, kPageInitialColorForWalk, finder);
    if (finder.sx != null) {
      return 2 * width * finder.sx!;
    }
  }
  return fallback;
}

const kPageInitialColorForWalk = Color(0xFF000000);

class _FirstUse implements SceneVisitor {
  _FirstUse(this.glyphId);
  final String glyphId;
  double? sx;

  @override
  bool enterGroup(SceneNode node, Color inheritedColor, Color color) =>
      sx == null;

  @override
  void visitLeaf(SceneChild leaf, Color color) {
    if (sx == null && leaf is SceneGlyphUse && leaf.glyphId == glyphId) {
      sx = leaf.sx;
    }
  }

  @override
  void exitGroup(SceneNode node) {}
}

/// Onde a haste termina (`edgeX` "fim"): a borda direita da página mais a
/// largura da haste, de modo que ela saia inteira. Em unidades de viewBox.
double sweepEndX(ScenePage page, double barWidth) =>
    xFromPagePx(page.widthPx.toDouble(), page) + barWidth;

/// Controle de navegação de um [ScoreView].
///
/// Passe o mesmo objeto ao `ScoreView` e use os métodos daqui; notifica a cada
/// mudança **efetiva** de página (nunca por frame).
class ScoreViewController extends ChangeNotifier {
  ScoreViewState? _state;

  ScoreViewState get _s {
    final s = _state;
    if (s == null) {
      throw StateError('ScoreViewController não está ligado a um ScoreView');
    }
    return s;
  }

  bool get isAttached => _state != null;

  /// Largura efetiva da haste e teto de cada movimento (o `ScorePlayer` os lê
  /// daqui para não duplicar as constantes).
  double get barWidth => _s.barWidth;
  Duration get maxSweepDuration => _s.widget.maxSweepDuration;

  /// A página em repouso (ou, durante a virada, a que está sendo varrida).
  /// Sempre uma página **normal** (D-ALT-INDICE) — para saber se uma
  /// alternativa está exibida, use [displayedPage].
  int get currentPage => _state?._current ?? 0;

  /// A página realmente exibida agora: normal (`sequence == null`) ou uma
  /// alternativa que [showPage] pediu (P03b/P04b). `currentPage`/`goToPage`
  /// continuam falando só de páginas normais (D-ALT-INDICE); `displayedPage`
  /// é o que aparece na tela.
  PageRef get displayedPage => _state?.displayedPage ?? const PageRef(0);

  /// Mostra [ref] (normal ou alternativa) - API do player (P04b). Com uma
  /// [PageRef] normal, é o [goToPage] de hoje (sem animação). Com uma
  /// alternativa, `currentPage` passa a ser a página normal do primeiro
  /// compasso dela (D-ALT-INDICE: o usuário continua vendo "página X" com
  /// sentido), mas a tela mostra a alternativa.
  void showPage(PageRef ref) => _s.showPage(ref);

  int get pageCount => _s.widget.document.pages.length;

  ScorePageMode get mode => _s.widget.mode;

  /// Há uma virada (haste ou trilha) em curso.
  bool get isTurning => _state?.isTurning ?? false;

  /// Vai para a página [index], **instantaneamente**, cancelando qualquer
  /// virada em curso. Fora do intervalo não lança: satura na primeira/última
  /// página. Devolve o índice efetivo.
  int goToPage(int index) => _s.goToPage(index);

  /// Avança uma página. Em `pagedSweep` faz a varredura inteira em
  /// `maxSweepDuration` (ou, com uma em curso, a conclui); em `pagedSlide`
  /// desliza; `animate: false` é instantâneo. Na última página satura.
  /// Devolve a página para a qual vai.
  int nextPage({bool animate = true}) => _s.nextPage(animate: animate);

  /// Volta uma página, instantaneamente (só `pagedSlide` anima). Na primeira
  /// satura. Devolve a página para a qual vai.
  int previousPage({bool animate = true}) => _s.previousPage(animate: animate);

  /// Anima a borda da haste até [edgeX] (unidades de viewBox da página
  /// corrente). Só em `pagedSweep`, e ignorado na última página.
  Future<void> sweepTo(double edgeX, {Duration? duration}) =>
      _s.sweepTo(edgeX, duration: duration);

  /// Leva a haste ao fim e completa a virada.
  Future<void> finishSweep({Duration? duration}) =>
      _s.finishSweep(duration: duration);

  /// Leva a tela até o elemento [id]. Modo paginado: `goToPage` da página dele.
  /// Modo contínuo: rola até a bbox ficar visível, com [alignment] (0 = topo,
  /// 0,5 = centro, 1 = pé). [id] é resolvido pela regra do sufixo (E02a:
  /// `ScoreGeometry.elementOf`), então um `-rend2` do timemap rola até a base
  /// na cena. Devolve `false`, sem lançar e sem mexer na posição, se [id] não
  /// resolve a nada na cena ou se a vista ainda não foi montada.
  bool scrollToId(
    String id, {
    double alignment = 0.5,
    Duration duration = Duration.zero,
  }) => _s.scrollToId(id, alignment: alignment, duration: duration);

  void _notifyPage() => notifyListeners();
}

class ScoreView extends StatefulWidget {
  const ScoreView({
    super.key,
    required this.document,
    this.controller,
    this.viewController,
    this.mode = ScorePageMode.pagedSweep,
    this.onPageChanged,
    this.initialPage = 0,
    this.animatableIds,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.haloSigmaScale = 1.0,
    this.barColor = kDefaultBarColor,
    this.barWidth,
    this.maxSweepDuration = kDefaultMaxSweepDuration,
    this.slideDuration = const Duration(milliseconds: 300),
    this.curtain,
    this.overlayIds = const [],
    this.overlayBuilder,
    this.onElementTap,
    this.tapClasses,
  });

  final VsbDocument document;

  /// Cor por id e destaques (A01c/A02b), compartilhado por todas as páginas.
  final ScoreController? controller;

  /// Navegação (`goToPage`, `nextPage`, ...).
  final ScoreViewController? viewController;

  final ScorePageMode mode;

  /// Chamado uma vez por mudança efetiva de página, nunca por frame.
  final ValueChanged<int>? onPageChanged;

  final int initialPage;
  final Set<String>? animatableIds;
  final Color? backgroundColor;

  /// Controle do usuário sobre a largura do halo (A02d), repassado a cada
  /// `ScorePageView`. Ver [ScorePageView.haloSigmaScale].
  final double haloSigmaScale;

  /// Cor da haste (A03b). Azul opaco de alto contraste; parâmetro, não
  /// constante espalhada.
  final Color barColor;

  /// Largura da haste em unidades de viewBox; `null` = `2 ×` a cabeça de nota
  /// preta ([defaultBarWidth]).
  final double? barWidth;

  /// Duração de cada movimento da haste no modo manual (`nextPage` sem
  /// `curtain` externo). O `D` da regra de A05b é `min(este teto, compasso/4)`.
  final Duration maxSweepDuration;

  /// Duração da transição de `pagedSlide`.
  final Duration slideDuration;

  /// A haste dirigida de fora (A05b). `null` no valor (ou `edgeX` fora do
  /// intervalo aberto) é o repouso.
  final ValueListenable<SweepCurtain?>? curtain;

  /// Overlays e toque (A04b), repassados a cada `ScorePageView`.
  final Iterable<String> overlayIds;
  final Widget? Function(BuildContext context, String id, Rect rect)?
  overlayBuilder;
  final void Function(String id)? onElementTap;
  final Set<String>? tapClasses;

  @override
  State<ScoreView> createState() => ScoreViewState();
}

class ScoreViewState extends State<ScoreView> with TickerProviderStateMixin {
  final PictureStats _stats = PictureStats();
  final Map<PageRef, GlobalKey> _keys = {};

  int _current = 0;

  /// Página exibida quando **não** é a normal [_current] (P03b): uma
  /// alternativa que [showPage] pediu. `null` em repouso normal.
  PageRef? _shown;

  /// A página realmente na tela: [_shown], ou a normal [_current].
  PageRef get displayedPage => _shown ?? PageRef(_current);

  // Haste manual (sweepTo/finishSweep/nextPage sem curtain externo).
  final ValueNotifier<SweepCurtain?> _manual = ValueNotifier(null);
  late final AnimationController _sweepAnim = AnimationController(vsync: this);
  Completer<void>? _sweepDone;

  // Trilha horizontal (pagedSlide).
  late final AnimationController _slideAnim = AnimationController(vsync: this);
  PageRef? _slideTo;
  int _slideDir = 1;

  // Rolagem contínua.
  ScrollController? _scroll;
  double _layoutWidth = 0;
  double _viewportHeight = 0;
  List<double> _tops = const [0];

  double? _barWidth;

  // Durante `didUpdateWidget` (fase de build) os listeners não podem chamar
  // `setState`.
  bool _inUpdate = false;

  VsbDocument get _doc => widget.document;
  int get _pageCount => _doc.pages.length;

  /// Contadores de `Picture` das páginas montadas por esta vista (todas
  /// somadas). Em paginado só a página corrente (e a vizinha durante uma
  /// virada) tem `Picture` vivo.
  PictureStats get pictureStats => _stats;

  bool get isTurning =>
      _sweepAnim.isAnimating ||
      _slideAnim.isAnimating ||
      _activeCurtain != null;

  double get barWidth =>
      widget.barWidth ?? (_barWidth ??= defaultBarWidth(_doc));

  GlobalKey _keyOf(PageRef ref) => _keys.putIfAbsent(ref, GlobalKey.new);

  // -------------------------------------------------------------------------
  // Ciclo de vida
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage.clamp(0, _pageCount - 1);
    widget.viewController?._state = this;
    widget.curtain?.addListener(_onCurtainChanged);
    _manual.addListener(_onCurtainChanged);
    _sweepAnim.addListener(_onSweepTick);
    _sweepAnim.addStatusListener(_onSweepStatus);
    _slideAnim.addStatusListener(_onSlideStatus);
    if (widget.mode == ScorePageMode.continuousScroll) {
      _scroll = _newScroll();
      if (_current > 0) {
        _pendingJump = _current;
      }
    }
  }

  ScrollController _newScroll() {
    final c = ScrollController();
    c.addListener(_onScroll);
    return c;
  }

  @override
  void didUpdateWidget(ScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _inUpdate = true;
    try {
      _applyWidgetUpdate(oldWidget);
    } finally {
      _inUpdate = false;
    }
  }

  void _applyWidgetUpdate(ScoreView oldWidget) {
    if (oldWidget.viewController != widget.viewController) {
      if (oldWidget.viewController?._state == this) {
        oldWidget.viewController?._state = null;
      }
      widget.viewController?._state = this;
    }
    if (oldWidget.curtain != widget.curtain) {
      oldWidget.curtain?.removeListener(_onCurtainChanged);
      widget.curtain?.addListener(_onCurtainChanged);
    }
    if (oldWidget.document != widget.document) {
      _barWidth = null;
      _keys.clear();
      _shown = null;
      _current = _current.clamp(0, _pageCount - 1);
      _cancelTurn();
    }
    if (oldWidget.mode != widget.mode) {
      _cancelTurn();
      if (widget.mode == ScorePageMode.continuousScroll) {
        _scroll ??= _newScroll();
        _pendingJump = _current;
      } else {
        _scroll?.dispose();
        _scroll = null;
      }
    }
  }

  @override
  void dispose() {
    // Uma vista nova pode já ter assumido o controller (troca de `key`).
    if (widget.viewController?._state == this) {
      widget.viewController?._state = null;
    }
    widget.curtain?.removeListener(_onCurtainChanged);
    _manual.removeListener(_onCurtainChanged);
    _sweepAnim.dispose();
    _slideAnim.dispose();
    _manual.dispose();
    _scroll?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Página corrente
  // -------------------------------------------------------------------------

  void _setCurrent(int page) {
    if (page == _current) {
      return;
    }
    _current = page;
    widget.onPageChanged?.call(page);
    widget.viewController?._notifyPage();
  }

  void _cancelTurn() {
    if (_sweepAnim.isAnimating) {
      _sweepAnim.stop();
    }
    _completeSweepFuture();
    if (_slideAnim.isAnimating) {
      _slideAnim.stop();
    }
    _slideTo = null;
    if (_manual.value != null) {
      _manual.value = null;
    }
  }

  int goToPage(int index) {
    final target = index.clamp(0, _pageCount - 1);
    _shown = null;
    _cancelTurn();
    if (widget.mode == ScorePageMode.continuousScroll) {
      _setCurrent(target);
      _jumpToPage(target);
    } else {
      _setCurrent(target);
      setState(() {});
    }
    return target;
  }

  int nextPage({bool animate = true}) {
    _shown = null;
    final from = _current;
    if (widget.mode == ScorePageMode.continuousScroll) {
      return goToPage(from + 1);
    }
    if (_slideAnim.isAnimating) {
      // Conclui a transição em curso em vez de empilhar outra.
      _slideAnim.value = 1;
      return _current;
    }
    if (from >= _pageCount - 1) {
      return from;
    }
    if (!animate) {
      return goToPage(from + 1);
    }
    if (widget.mode == ScorePageMode.pagedSweep) {
      if (_manual.value != null || _sweepAnim.isAnimating) {
        unawaited(finishSweep());
      } else {
        unawaited(
          _animateSweep(0, _endX(PageRef(from)), widget.maxSweepDuration),
        );
      }
      return from + 1;
    }
    _startSlide(PageRef(from + 1));
    return from + 1;
  }

  int previousPage({bool animate = true}) {
    _shown = null;
    final from = _current;
    if (widget.mode == ScorePageMode.pagedSlide &&
        animate &&
        from > 0 &&
        !_slideAnim.isAnimating) {
      _startSlide(PageRef(from - 1));
      return from - 1;
    }
    return goToPage(from - 1);
  }

  // -------------------------------------------------------------------------
  // Página exibida (P03b): normal ou alternativa
  // -------------------------------------------------------------------------

  /// `true` se [ref] existe (índice dentro do intervalo, sequência dentro de
  /// `document.alternates`).
  bool _refInRange(PageRef ref) {
    final sequence = ref.sequence;
    if (sequence == null) {
      return ref.index >= 0 && ref.index < _pageCount;
    }
    if (sequence < 0 || sequence >= _doc.alternates.length) {
      return false;
    }
    return ref.index >= 0 && ref.index < _doc.alternates[sequence].pages.length;
  }

  /// Aplica [ref] a `_shown`/`_current`, sem cancelar nenhuma virada em
  /// curso (decisão de quem chama) nem chamar `setState`. Com uma
  /// alternativa, `_current` vira a página normal do primeiro compasso dela
  /// (D-ALT-INDICE) — a mesma pesquisa de `ScenePage.firstMeasureId` +
  /// `ScoreGeometry.pageOf` que P02b faz em C++ para achar `firstOfNormalPage`.
  void _applyDisplayed(PageRef ref) {
    final sequence = ref.sequence;
    if (sequence == null) {
      _shown = null;
      _setCurrent(ref.index);
      return;
    }
    _shown = ref;
    final firstMeasureId =
        _doc.alternates[sequence].pages[ref.index].firstMeasureId;
    final normalPage = firstMeasureId == null
        ? _current
        : (_doc.geometry.pageOf(firstMeasureId) ?? _current);
    _setCurrent(normalPage);
  }

  /// Mostra [ref] (normal ou alternativa) — API do player (P04b/A05b).
  void showPage(PageRef ref) {
    if (widget.mode == ScorePageMode.continuousScroll) {
      // Fora de escopo (P03b): rolagem contínua não mostra alternativas —
      // uma alternativa vira a página normal equivalente (D-ALT-INDICE).
      if (!ref.isAlternate) {
        goToPage(ref.index);
        return;
      }
      final firstMeasureId =
          _doc.alternates[ref.sequence!].pages[ref.index].firstMeasureId;
      goToPage(
        firstMeasureId == null
            ? _current
            : (_doc.geometry.pageOf(firstMeasureId) ?? _current),
      );
      return;
    }
    _cancelTurn();
    _applyDisplayed(ref);
    setState(() {});
  }

  // -------------------------------------------------------------------------
  // Haste
  // -------------------------------------------------------------------------

  double _endX(PageRef ref) => sweepEndX(_doc.pageAt(ref), barWidth);

  /// [c] é uma haste válida: página e destino dentro do documento, com um
  /// destino diferente da própria página (E03a: a última página só tem
  /// haste com destino explícito — sem ele, `pageIndex + 1` não existiria).
  bool _isValidCurtain(SweepCurtain c) {
    if (!_refInRange(c.page)) {
      return false;
    }
    final target = c.target;
    return _refInRange(target) && target != c.page;
  }

  /// A haste em vigor, ou `null` (repouso): a externa, se não-nula, senão a
  /// manual — sempre restrita ao intervalo aberto `(0, fim)`, ao modo
  /// `pagedSweep` e a uma página com destino válido (E03a).
  SweepCurtain? get _activeCurtain {
    if (widget.mode != ScorePageMode.pagedSweep) {
      return null;
    }
    final c = widget.curtain?.value ?? _manual.value;
    if (c == null || !_isValidCurtain(c)) {
      return null;
    }
    if (c.edgeX <= 0 || c.edgeX >= _endX(c.page)) {
      return null;
    }
    return c;
  }

  void _onCurtainChanged() {
    if (widget.mode != ScorePageMode.pagedSweep || !mounted || _inUpdate) {
      return;
    }
    final c = widget.curtain?.value ?? _manual.value;
    if (c != null &&
        _isValidCurtain(c) &&
        c.page == displayedPage &&
        c.edgeX >= _endX(c.page)) {
      // Conclusão: o destino vira a página exibida e a haste some.
      _cancelSweepAnim();
      if (_manual.value != null) {
        _manual.value = null;
      }
      _applyDisplayed(c.target);
      setState(() {});
      return;
    }
    final active = _activeCurtain;
    if (active != null) {
      _applyDisplayed(active.page);
    }
    setState(() {});
  }

  void _cancelSweepAnim() {
    if (_sweepAnim.isAnimating) {
      _sweepAnim.stop();
    }
    _completeSweepFuture();
  }

  void _completeSweepFuture() {
    final done = _sweepDone;
    _sweepDone = null;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  double _sweepFrom = 0;
  double _sweepTo = 0;
  int _sweepPage = 0;

  Future<void> _animateSweep(double from, double to, Duration duration) {
    _cancelSweepAnim();
    if (widget.mode != ScorePageMode.pagedSweep || _current >= _pageCount - 1) {
      return Future.value();
    }
    _sweepFrom = from;
    _sweepTo = to;
    _sweepPage = _current;
    final done = _sweepDone = Completer<void>();
    _sweepAnim.duration = duration;
    if (duration == Duration.zero) {
      _sweepAnim.value = 1;
      _completeSweepFuture();
      return done.future;
    }
    _sweepAnim.forward(from: 0);
    return done.future;
  }

  void _onSweepTick() {
    final t = Curves.easeInOut.transform(_sweepAnim.value);
    _manual.value = SweepCurtain(
      pageIndex: _sweepPage,
      edgeX: _sweepFrom + (_sweepTo - _sweepFrom) * t,
    );
  }

  void _onSweepStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completeSweepFuture();
    }
  }

  Future<void> sweepTo(double edgeX, {Duration? duration}) {
    if (widget.mode != ScorePageMode.pagedSweep) {
      return Future.value();
    }
    final from = _manual.value?.pageIndex == _current
        ? _manual.value!.edgeX
        : 0.0;
    return _animateSweep(from, edgeX, duration ?? widget.maxSweepDuration);
  }

  Future<void> finishSweep({Duration? duration}) {
    if (widget.mode != ScorePageMode.pagedSweep || _current >= _pageCount - 1) {
      return Future.value();
    }
    final from = _manual.value?.pageIndex == _current
        ? _manual.value!.edgeX
        : 0.0;
    return _animateSweep(
      from,
      _endX(PageRef(_current)),
      duration ?? widget.maxSweepDuration,
    );
  }

  // -------------------------------------------------------------------------
  // Trilha horizontal
  // -------------------------------------------------------------------------

  void _startSlide(PageRef to) {
    _slideDir = (to.sequence == null && to.index < _current) ? -1 : 1;
    _slideTo = to;
    setState(() {});
    _slideAnim
      ..duration = widget.slideDuration
      ..forward(from: 0);
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _slideTo != null) {
      final to = _slideTo!;
      _slideTo = null;
      _applyDisplayed(to);
      setState(() {});
    }
  }

  // -------------------------------------------------------------------------
  // Rolagem contínua
  // -------------------------------------------------------------------------

  int? _pendingJump;

  bool _programmatic = false;

  void _onScroll() {
    final scroll = _scroll;
    if (_programmatic || scroll == null || !scroll.hasClients) {
      return;
    }
    final center = scroll.offset + _viewportHeight / 2;
    var page = 0;
    for (var i = 0; i < _pageCount; i++) {
      if (_tops[i] <= center) {
        page = i;
      }
    }
    _setCurrent(page);
  }

  void _jumpToPage(int page) {
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients && _tops.length > page) {
      _jump(scroll, _clampScroll(_tops[page]));
    } else {
      _pendingJump = page;
    }
  }

  void _jump(ScrollController scroll, double offset) {
    _programmatic = true;
    try {
      scroll.jumpTo(offset);
    } finally {
      _programmatic = false;
    }
  }

  double _clampScroll(double offset) {
    final scroll = _scroll!;
    final max = scroll.position.maxScrollExtent;
    return offset.clamp(0.0, max);
  }

  bool scrollToId(
    String id, {
    double alignment = 0.5,
    Duration duration = Duration.zero,
  }) {
    final ref = _doc.geometry.elementOf(id);
    if (ref == null) {
      return false;
    }
    if (widget.mode != ScorePageMode.continuousScroll) {
      goToPage(ref.page);
      return true;
    }
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || _layoutWidth <= 0) {
      return false;
    }
    final rect = _doc.geometry.rectOf(ref, pageWidth: _layoutWidth);
    final a = alignment.clamp(0.0, 1.0);
    final target = _clampScroll(
      _tops[ref.page] + rect.top + a * rect.height - a * _viewportHeight,
    );
    if (duration == Duration.zero) {
      _jump(scroll, target);
      _setCurrent(ref.page);
    } else {
      unawaited(
        scroll.animateTo(target, duration: duration, curve: Curves.easeInOut),
      );
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Construção
  // -------------------------------------------------------------------------

  Widget _page(PageRef ref, {Key? key}) => ScorePageView(
    key: key ?? _keyOf(ref),
    document: _doc,
    pageIndex: ref.index,
    sequence: ref.sequence,
    controller: widget.controller,
    animatableIds: widget.animatableIds,
    backgroundColor: widget.backgroundColor,
    haloSigmaScale: widget.haloSigmaScale,
    stats: _stats,
    overlayIds: widget.overlayIds,
    overlayBuilder: widget.overlayBuilder,
    onElementTap: widget.onElementTap,
    tapClasses: widget.tapClasses,
  );

  /// Tamanho da página [ref] desenhada dentro de [box]: a maior escala que
  /// a mantém inteira (`meet`). Com a caixa do tamanho da página a escala é
  /// exatamente 1.
  Size _fit(PageRef ref, Size box) {
    final p = _doc.pageAt(ref);
    final w = p.widthPx.toDouble();
    final h = p.heightPx.toDouble();
    final s = box.width.isFinite && box.height.isFinite
        ? (box.width / w < box.height / h ? box.width / w : box.height / h)
        : (box.width.isFinite ? box.width / w : 1.0);
    return Size(w * s, h * s);
  }

  Widget _centered(PageRef ref, Size box, {Key? key}) => Center(
    child: SizedBox.fromSize(
      size: _fit(ref, box),
      child: _page(ref, key: key),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        switch (widget.mode) {
          case ScorePageMode.continuousScroll:
            return _buildContinuous(constraints);
          case ScorePageMode.pagedSlide:
            return _buildSlide(constraints);
          case ScorePageMode.pagedSweep:
            return _buildSweep(constraints);
        }
      },
    );
  }

  Size _box(BoxConstraints c) {
    final page = _doc.pageAt(displayedPage);
    return Size(
      c.hasBoundedWidth ? c.maxWidth : page.widthPx.toDouble(),
      c.hasBoundedHeight ? c.maxHeight : page.heightPx.toDouble(),
    );
  }

  Widget _buildSweep(BoxConstraints constraints) {
    final box = _box(constraints);
    final curtain = _activeCurtain;
    final a = curtain?.page ?? displayedPage;
    Widget stack;
    if (curtain == null) {
      stack = _centered(a, box);
    } else {
      final pageA = _doc.pageAt(a);
      final size = _fit(a, box);
      final s = size.width / pageA.widthPx;
      final offset = Offset(
        (box.width - size.width) / 2,
        (box.height - size.height) / 2,
      );
      final edge = offset.dx + xToPagePx(curtain.edgeX, pageA) * s;
      final barPx = barWidth * pageA.fit.scale * s;
      final barLeft = (edge - barPx).clamp(offset.dx, offset.dx + size.width);
      final barRight = edge.clamp(offset.dx, offset.dx + size.width);
      stack = Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          _centered(curtain.target, box),
          ClipRect(clipper: _RightOfClipper(edge), child: _centered(a, box)),
          if (barRight > barLeft)
            Positioned(
              left: barLeft,
              top: offset.dy,
              width: barRight - barLeft,
              height: size.height,
              child: IgnorePointer(child: ColoredBox(color: widget.barColor)),
            ),
        ],
      );
    }
    return SizedBox.fromSize(size: box, child: stack);
  }

  Widget _buildSlide(BoxConstraints constraints) {
    final box = _box(constraints);
    final to = _slideTo;
    if (to == null) {
      return SizedBox.fromSize(size: box, child: _centered(displayedPage, box));
    }
    return SizedBox.fromSize(
      size: box,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _slideAnim,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_slideAnim.value);
            final dx = box.width * _slideDir;
            return Stack(
              textDirection: TextDirection.ltr,
              fit: StackFit.expand,
              children: [
                Transform.translate(
                  offset: Offset(-dx * t, 0),
                  child: _centered(displayedPage, box),
                ),
                Transform.translate(
                  offset: Offset(dx * (1 - t), 0),
                  child: _centered(to, box),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContinuous(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _doc.pages[0].widthPx.toDouble();
    final viewport = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : _doc.pages[0].heightPx.toDouble();
    _layoutWidth = width;
    _viewportHeight = viewport;
    final heights = [
      for (final p in _doc.pages) width * p.heightPx / p.widthPx,
    ];
    final tops = <double>[0];
    for (final h in heights) {
      tops.add(tops.last + h);
    }
    _tops = tops;
    final pending = _pendingJump;
    if (pending != null) {
      _pendingJump = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_scroll?.hasClients ?? false)) {
          _jump(
            _scroll!,
            _clampScroll(_tops[pending.clamp(0, _pageCount - 1)]),
          );
        }
      });
    }
    // Janela de `Picture` vivos: as páginas que cruzam a viewport mais uma
    // página de cada lado (cacheExtent de uma altura de página).
    final cache = heights.reduce((a, b) => a > b ? a : b);
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: _pageCount,
      scrollCacheExtent: ScrollCacheExtent.pixels(cache),
      itemExtentBuilder: (i, _) => heights[i],
      itemBuilder: (context, i) => _page(PageRef(i), key: ValueKey<int>(i)),
    );
  }
}

/// Deixa passar só `x >= edge` (pixels do próprio widget).
class _RightOfClipper extends CustomClipper<Rect> {
  const _RightOfClipper(this.edge);
  final double edge;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(edge, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightOfClipper oldClipper) => oldClipper.edge != edge;
}

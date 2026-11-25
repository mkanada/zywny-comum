// `ScorePageCubit`: o estado de uma página da partitura (BL26; antes era o
// `State` do `ScorePageView`). Guarda as camadas da página (`PageLayers`, os
// `Picture` estáticos), os ids que o controller de cores promove a dinâmicos e
// as folhas que ele esconde.
//
// O `ScoreCubit` avisa pelo `stream` (assíncrono). Quando a promoção ou as folhas
// escondidas mudam, este cubit refaz as camadas e sobe o `serial`, para o pintor
// repintar. O pintor lê [layers] ao pintar; nenhuma decisão espera o `stream`.
//
// O cubit mora pelo tempo da página na árvore (o `ScorePageView` o põe em volta
// dela, com um `BlocProvider`). A cada build, a página passa ao cubit os seus
// parâmetros ([sync]): mudar o documento, a página, a sequência, o controller ou
// os ids dinâmicos refaz as camadas, e a memória de `Picture` continua a mesma.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'model.dart';
import 'page_layers.dart';
import 'score_cubit.dart';
import 'segmentation.dart';

/// Estado de [ScorePageCubit]: só o `serial`, que sobe a cada repintura pedida
/// (as camadas em si ficam no cubit, como no [ScoreCubit]).
class ScorePageState extends Equatable {
  const ScorePageState(this.serial);

  final int serial;

  @override
  List<Object?> get props => [serial];
}

class ScorePageCubit extends Cubit<ScorePageState> {
  ScorePageCubit({
    required this.document,
    required this.pageIndex,
    this.sequence,
    this.controller,
    this.animatableIds,
    PictureStats? stats,
  }) : _stats = stats ?? PictureStats(),
       super(const ScorePageState(0)) {
    controller?.attachDocument(document);
    _listenColors();
    _collectPromotions();
    _rebuildLayers();
  }

  /// A página e o que a mostra (ver [sync]).
  VsbDocument document;
  int pageIndex;
  int? sequence;

  /// Cor por id e destaques (o `ScoreCubit` da partitura), ou `null`.
  ScoreCubit? controller;

  /// Ids que podem mudar de cor sem recompilar a página (`null`: os do timemap).
  Set<String>? animatableIds;

  /// Põe os parâmetros da página (o `ScorePageView` os dá a cada build). Nada
  /// muda: não faz nada. Documento, página, sequência ou ids dinâmicos novos:
  /// refaz as camadas (a promoção recomeça do zero). Controller novo: troca a
  /// assinatura das cores e refaz as camadas, que dependem dele.
  void sync({
    required VsbDocument document,
    required int pageIndex,
    int? sequence,
    ScoreCubit? controller,
    Set<String>? animatableIds,
  }) {
    if (isClosed) return;
    final structural =
        !identical(this.document, document) ||
        this.pageIndex != pageIndex ||
        this.sequence != sequence ||
        !setEquals(this.animatableIds, animatableIds);
    final otherController = !identical(this.controller, controller);
    if (!structural && !otherController) return;
    this.document = document;
    this.pageIndex = pageIndex;
    this.sequence = sequence;
    this.animatableIds = animatableIds;
    controller?.attachDocument(document);
    if (otherController) {
      this.controller = controller;
      _listenColors();
    }
    if (structural) _promoted.clear();
    _collectPromotions();
    _rebuildLayers();
  }

  void _listenColors() {
    _colorSub?.cancel();
    _colorSub = controller?.stream.listen((_) => _onControllerChanged());
  }

  final PictureStats _stats;
  PageLayers? _layers;

  /// Os ids que são dinâmicos agora: os de [animatableIds] mais os promovidos.
  Set<String> _dynamicIds = const {};

  /// Folhas da página que o controller manda não pintar (barra de ligação e
  /// linha suplementar de nota escondida, L02).
  Set<SceneChild> _skipLeaves = const {};

  /// Ids promovidos a dinâmicos porque o controller os colore (ver
  /// [_collectPromotions]).
  final Set<String> _promoted = {};

  StreamSubscription<ScoreState>? _colorSub;

  /// A página, como a vê o documento.
  ScenePage get page =>
      document.pageAt(PageRef(pageIndex, sequence: sequence));

  /// As camadas em uso. O pintor lê ao pintar, então uma promoção vale no
  /// quadro seguinte, sem recriar o pintor.
  PageLayers get layers => _layers!;

  /// Quantos `Picture` estáticos já foram gravados (todas as gerações de cache
  /// somadas). Não muda quando uma cor muda.
  @visibleForTesting
  int get pictureBuilds => _stats.builds;

  /// Quantos `Picture` estáticos já foram descartados.
  @visibleForTesting
  int get pictureDisposals => _stats.disposals;

  @visibleForTesting
  PictureStats get pictureStats => _stats;

  void _rebuildLayers() {
    final old = _layers;
    _dynamicIds = {
      ...(animatableIds ??
          animatableIdsFromTimemap(document.timemap, document: document)),
      ..._promoted,
    };
    _skipLeaves = controller?.hiddenLeavesOf(page) ?? const {};
    _layers = PageLayers(
      page,
      document.glyphs,
      animatableIds: _dynamicIds,
      skipLeaves: _skipLeaves,
      glyphCache: document.glyphCache,
      stats: _stats,
    );
    old?.dispose();
  }

  void _onControllerChanged() {
    if (isClosed) return;
    final promoted = _collectPromotions();
    final leavesChanged = _skipLeavesChanged();
    if (promoted || leavesChanged) {
      _rebuildLayers();
      _repaint();
    }
  }

  /// O controller esconde outras formas desta página que não têm id (barra de
  /// ligação e traços de linha suplementar)? Só então os `Picture` estáticos são
  /// recompilados. O controller devolve o mesmo `Set` enquanto nada muda, então o
  /// caso comum (um destaque por quadro) custa uma comparação.
  bool _skipLeavesChanged() {
    final next = controller?.hiddenLeavesOf(page) ?? const {};
    if (identical(next, _skipLeaves)) {
      return false;
    }
    if (next.length != _skipLeaves.length ||
        !next.every(_skipLeaves.contains)) {
      return true;
    }
    _skipLeaves = next; // igual em conteúdo: guarda o novo objeto e segue
    return false;
  }

  /// Se o controller tem cor para um id que existe nesta página mas está num
  /// `Picture` estático, marca o id para promoção a dinâmico. Devolve se houve
  /// promoção nova (e as camadas precisam ser refeitas).
  bool _collectPromotions() {
    final c = controller;
    if (c == null || c.colors.isEmpty) {
      return false;
    }
    final byId = page.byId;
    var added = false;
    for (final id in c.colors.keys) {
      if (!_dynamicIds.contains(id) &&
          !_promoted.contains(id) &&
          byId.containsKey(id)) {
        _promoted.add(id);
        added = true;
      }
    }
    return added;
  }

  /// Sobe o `serial`: o pintor (um `BlocRepaint` do cubit) repinta.
  void _repaint() {
    if (isClosed) return;
    emit(ScorePageState(state.serial + 1));
  }

  @override
  Future<void> close() {
    _colorSub?.cancel();
    _colorSub = null;
    _layers?.dispose();
    _layers = null;
    return super.close();
  }
}

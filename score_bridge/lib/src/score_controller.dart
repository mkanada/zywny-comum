// `ScoreController`: cor por `xml:id` em runtime (A01c) e destaques animados
// (A02b).
//
// O controller é um `Listenable` que o `ScorePageView` liga ao `repaint:` do
// `CustomPainter`: mudar uma cor repinta sem `setState` e sem reconstruir
// nenhum widget. **Toda operação pública notifica no máximo uma vez** (e nada
// quando nada mudou), e o `Ticker` dos destaques notifica uma vez por frame,
// não uma por nota.
//
// MODELO DE COR de um id, em ordem de precedência:
//   1. a cor da animação, enquanto há um destaque ativo no id;
//   2. a cor "fixa" definida por [setColor];
//   3. a cor original do nó na cena (a herdada, com o `@color` do MEI).
// [setColor] muda, portanto, a **cor de repouso**: o destaque parte dela e
// volta para ela ao terminar. [clearColor] devolve a cor original — e, se há
// um destaque em curso, o `release` dele passa a ir para a cor original.
//
// IDS: com um documento associado ([attachDocument], que o `ScorePageView`
// faz sozinho), todo método público resolve o id recebido com
// `VsbDocument.sceneIdOf` (E02a) antes de mais nada — um id expandido do
// timemap (`abc-rend2`) vira o id da cena (`abc`), pela regra do sufixo
// (D-EXPMAP). Um id que não resolve a nada na cena é ignorado em silêncio:
// lançar exceção quebraria o playback. Sem documento não há como resolver
// nem saber se um id existe, e tudo é aceito como está.
//
// Estado (cor fixa, destaque, halo) é sempre indexado pelo id **da cena**:
// `setColor('x-rend2', …)` pinta `x` nas duas passagens, porque é o mesmo
// desenho.
//
// IDS NÃO-ANIMÁVEIS: um id fora de `animatableIds` está dentro de um `Picture`
// estático e, sozinho, não mudaria de cor. O `ScorePageView` **promove** o id
// a dinâmico quando o controller passa a ter uma cor para ele e o id existe na
// página, recompilando os `Picture` dessa página (uma vez por promoção; o
// custo aparece em `pictureBuilds`). Nada é ignorado em silêncio, mas o caminho
// barato é declarar os ids em `animatableIds` (por padrão, os do timemap).
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'highlight_engine.dart';
import 'model.dart';
import 'scene_painter.dart' show kPageInitialColor;
import 'scene_walk.dart';

/// Cor de destaque padrão de [ScoreController.highlight].
const kDefaultHighlightColor = ui.Color(0xFFD32F2F);

class _OriginalColors implements SceneVisitor {
  final Map<String, ui.Color> colors = {};

  @override
  bool enterGroup(SceneNode node, ui.Color inheritedColor, ui.Color color) {
    final id = node.id;
    if (id != null) {
      colors[id] = color;
    }
    return true;
  }

  @override
  void visitLeaf(SceneChild leaf, ui.Color color) {}

  @override
  void exitGroup(SceneNode node) {}
}

class _OwnTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'ScoreController');
}

class ScoreController extends ChangeNotifier {
  ScoreController({VsbDocument? document}) {
    if (document != null) {
      attachDocument(document);
    }
  }

  VsbDocument? _document;
  Map<String, ui.Color>? _originals;

  final Map<String, ui.Color> _fixed = {};
  final Map<String, ui.Color> _effective = {};
  late final Map<String, ui.Color> _effectiveView = UnmodifiableMapView(
    _effective,
  );
  final Set<String> _animatedIds = {};

  /// Halo (A02d): só as notas com destaque ativo agora, nunca as de cor fixa.
  final Map<String, ui.Color> _halo = {};
  late final Map<String, ui.Color> _haloView = UnmodifiableMapView(_halo);

  final HighlightEngine _engine = HighlightEngine();
  Ticker? _ticker;
  Duration _epoch = Duration.zero;
  Duration _now = Duration.zero;
  bool _disposed = false;

  /// Associa o documento cujas páginas o controller pinta. Idempotente para o
  /// mesmo documento. Necessário para resolver a cor original de um nó e para
  /// ignorar ids que não existem.
  void attachDocument(VsbDocument document) {
    if (identical(_document, document)) {
      return;
    }
    _document = document;
    _originals = null;
  }

  Map<String, ui.Color> get _originalColors {
    final cached = _originals;
    if (cached != null) {
      return cached;
    }
    final visitor = _OriginalColors();
    for (final page in _document?.pages ?? const <ScenePage>[]) {
      walkScene(page.root, kPageInitialColor, visitor);
    }
    return _originals = visitor.colors;
  }

  /// Ponto de entrada único de todo id recebido de fora: resolve um id
  /// expandido do timemap (`-rend<N>`) ao id da cena (E02a). Sem documento,
  /// devolve [id] sem mudar (não há como resolver).
  String _resolve(String id) => _document?.sceneIdOf(id) ?? id;

  bool _known(String id) =>
      _document == null || _originalColors.containsKey(id);

  ui.Color _originalOf(String id) =>
      _originalColors[id] ?? const ui.Color(0xFF000000);

  /// A cor de repouso de [id]: a fixa, se houver; senão a original.
  ui.Color _baseOf(String id) => _fixed[id] ?? _originalOf(id);

  /// A cor que sobrepõe a original de [id] agora (animação ou fixa), ou
  /// `null` quando o nó está com a cor original.
  ui.Color? colorOf(String id) => _effective[_resolve(id)];

  /// Todas as cores que sobrepõem a cena agora, por `id`. Somente leitura, e
  /// é o mesmo objeto a vida toda: o painter o consulta a cada frame.
  Map<String, ui.Color> get colors => _effectiveView;

  /// Cor do halo de cada nota com destaque ativo agora (A02d): a de destaque,
  /// com o alfa subindo no `attack` e caindo no `release`. Só as ids
  /// animadas — uma cor fixa (`setColor`) nunca tem halo. Somente leitura, e
  /// é o mesmo objeto a vida toda.
  Map<String, ui.Color> get haloColors => _haloView;

  // ---------------------------------------------------------------------
  // Cor instantânea (A01c)
  // ---------------------------------------------------------------------

  /// Define a cor de repouso de [id]. Recolore toda a subárvore do nó. Não
  /// interrompe um destaque em curso (a animação tem precedência e passa a
  /// voltar para esta cor).
  void setColor(String id, ui.Color color) {
    if (_setFixed(_resolve(id), color)) {
      notifyListeners();
    }
  }

  /// Define várias cores de repouso com **uma** notificação.
  void setColors(Map<String, ui.Color> colors) {
    var changed = false;
    colors.forEach(
      (id, color) => changed = _setFixed(_resolve(id), color) || changed,
    );
    if (changed) {
      notifyListeners();
    }
  }

  bool _setFixed(String id, ui.Color color) {
    if (!_known(id) || _fixed[id] == color) {
      return false;
    }
    _fixed[id] = color;
    if (_animatedIds.contains(id)) {
      _engine.rebase(id, color);
      return false; // a animação manda; o próximo frame já usa a nova base
    }
    _effective[id] = color;
    return true;
  }

  /// Devolve [id] à cor original. Com destaque em curso, o `release` passa a
  /// ir para a cor original.
  void clearColor(String id) {
    id = _resolve(id);
    if (_fixed.remove(id) == null) {
      return;
    }
    if (_animatedIds.contains(id)) {
      _engine.rebase(id, _originalOf(id));
      return;
    }
    _effective.remove(id);
    notifyListeners();
  }

  /// Volta a página ao repouso **agora**: apaga cores fixas e destaques, sem
  /// fade.
  void clearAll() {
    final changed = _effective.isNotEmpty || !_engine.isIdle;
    _fixed.clear();
    _effective.clear();
    _animatedIds.clear();
    _halo.clear();
    _engine.clear();
    _stopTicker();
    if (changed) {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Destaques animados (A02b)
  // ---------------------------------------------------------------------

  /// Acende [id]: `attack` até [color], `hold`, e `release` de volta à cor de
  /// repouso. Sem parâmetros é um destaque vermelho instantâneo que se apaga
  /// em 300 ms com `easeOut`. Numa nota já acesa, **reinicia** a animação
  /// dela sem tocar nas outras. Id inexistente é ignorado.
  void highlight(
    String id, {
    ui.Color color = kDefaultHighlightColor,
    Duration attack = Duration.zero,
    Duration hold = Duration.zero,
    Duration release = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) => highlightAll(
    [id],
    color: color,
    attack: attack,
    hold: hold,
    release: release,
    curve: curve,
  );

  /// [highlight] em vários ids, com **uma** notificação.
  void highlightAll(
    Iterable<String> ids, {
    ui.Color color = kDefaultHighlightColor,
    Duration attack = Duration.zero,
    Duration hold = Duration.zero,
    Duration release = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) {
    var any = false;
    for (final rawId in ids) {
      final id = _resolve(rawId);
      if (!_known(id)) {
        continue;
      }
      _engine.start(
        id,
        HighlightSpec(
          color: color,
          baseColor: _baseOf(id),
          attack: attack,
          hold: hold,
          release: release,
          curve: curve,
        ),
        _now,
      );
      any = true;
    }
    if (any) {
      _afterEngineChange();
    }
  }

  /// Começa agora o `release` de [id] (a partir da cor que ele tem), com a
  /// [duration] e a [curve] dadas ou, se ausentes, as do destaque.
  void release(String id, {Duration? duration, Curve? curve}) {
    _engine.stop(_resolve(id), _now, release: duration, curve: curve);
    _afterEngineChange();
  }

  /// Apaga todos os destaques **agora**, sem fade, preservando as cores fixas
  /// de [setColor] (diferente de [clearAll]). É o que o player usa no `seek`.
  void clearHighlights() {
    if (_engine.isIdle && _animatedIds.isEmpty) {
      return;
    }
    _engine.clear();
    final changed = _syncAnimated();
    _stopTicker();
    if (changed) {
      notifyListeners();
    }
  }

  /// [release] em todas as notas acesas.
  void releaseAll({Duration? duration, Curve? curve}) {
    _engine.stopAll(_now, release: duration, curve: curve);
    _afterEngineChange();
  }

  /// [id] tem um destaque em curso.
  bool isHighlighted(String id) => _engine.isActive(_resolve(id));

  /// Os ids com destaque em curso (em qualquer fase, `release` incluído).
  Iterable<String> get highlightedIds => _engine.activeIds;

  /// Quantas notas têm um destaque em curso.
  int get highlightedCount => _engine.activeCount;

  // ---------------------------------------------------------------------
  // Relógio
  // ---------------------------------------------------------------------

  /// O relógio só avança enquanto o `Ticker` roda: parado, [_now] fica
  /// congelado no último frame, e um destaque novo parte dele.
  @visibleForTesting
  bool get tickerActive => _ticker?.isActive ?? false;

  void _afterEngineChange() {
    final changed = _syncAnimated();
    if (_engine.isIdle) {
      _stopTicker();
    } else if (!tickerActive) {
      (_ticker ??= _OwnTickerProvider().createTicker(_onTick)).start();
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _onTick(Duration elapsed) {
    _now = _epoch + elapsed;
    final changed = _syncAnimated();
    if (_engine.isIdle) {
      _stopTicker();
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _stopTicker() {
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) {
      _epoch = _now;
      ticker.stop();
    }
  }

  /// Traz `_effective` para o instante [_now]: aplica as cores das notas
  /// ativas e restaura as que deixaram de estar. Devolve se algo mudou.
  bool _syncAnimated() {
    var colors = _engine.colorsAt(_now);
    if (_engine.isIdle) {
      // Tudo terminou: as cores exatas de repouso voltam pela remoção.
      colors = const {};
    }
    var changed = false;
    for (final id in _animatedIds) {
      // Também as que terminaram neste frame: o motor as devolve uma última
      // vez, mas com outras notas ainda acesas elas não podem ficar presas na
      // cor do último quadro.
      if (!colors.containsKey(id) || !_engine.isActive(id)) {
        final fixed = _fixed[id];
        if (fixed == null) {
          _effective.remove(id);
        } else {
          _effective[id] = fixed;
        }
        changed = true;
      }
    }
    _animatedIds.clear();
    for (final entry in colors.entries) {
      if (!_engine.isActive(entry.key)) {
        // Terminou neste frame: o motor devolve a base exata uma última vez,
        // mas o controller já volta o id ao repouso (cor fixa ou original).
        continue;
      }
      _animatedIds.add(entry.key);
      if (_effective[entry.key] != entry.value) {
        _effective[entry.key] = entry.value;
        changed = true;
      }
    }
    _halo
      ..clear()
      ..addAll(_engine.haloColorsAt(_now));
    return changed;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }
}

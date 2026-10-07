// Camada de nota fantasma (G05): estado das fantasmas na tela (aparece no
// note-on, some com fade depois do note-off) e o painter que as desenha por
// cima da página. O cálculo é ghost.dart; aqui só ciclo de vida e pintura.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter/scheduler.dart';

import 'ghost.dart';
import 'glyph_cache.dart';
import 'model.dart';

/// Cor padrão da fantasma (D-FANT: "cor diferente"); o host escolhe.
const kDefaultGhostColor = ui.Color(0xFFE65100);

/// Uma fantasma na tela, com a opacidade do instante.
class VisibleGhost {
  const VisibleGhost(this.ghost, this.opacity);
  final GhostNote ghost;
  final double opacity;
}

class _Entry {
  _Entry(this.pressedAt, {this.targetIds, this.side = 0});
  final List<String>? targetIds;
  final int side;
  GhostNote? ghost;
  final Duration pressedAt;
  Duration? releaseAt;
  double opacity = 1;
}

/// Uma tecla errada a desenhar fixa na partitura (a revisão do treino): a
/// coluna dos eventos [targetIds] e o [side] — `-1` tocada antes do tempo
/// (fantasma à esquerda da coluna), `1` depois (à direita), `0` sem noção de
/// tempo (em cima da coluna, como no modo espera).
@immutable
class GhostRequest {
  const GhostRequest({
    required this.key,
    required this.targetIds,
    this.side = 0,
  });

  final int key;
  final List<String> targetIds;
  final int side;
}

/// Quanto a fantasma de uma nota fora do tempo sai da coluna, em larguras
/// de cabeça de nota (de centro a centro), para a esquerda (antes do tempo)
/// ou para a direita (depois). No máximo meia cabeça: ela fica colada na
/// nota esperada, só escorregada para o lado.
const double kGhostSideOffsetHeads = 0.5;

class _OwnTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'GhostController');
}

/// Dono das fantasmas visíveis. Uma por tecla errada apertada; o conjunto é
/// recalculado (colisão entre fantasmas) quando uma tecla entra ou o evento
/// esperado muda, e uma tecla solta fica congelada enquanto some.
///
/// [fade] e [minVisible] são parâmetros do host (D-FANT-DURACAO); a
/// fantasma nunca some antes de [minVisible] desde o note-on, mesmo que a
/// tecla seja solta antes.
class GhostController extends ChangeNotifier {
  GhostController({
    this.color = kDefaultGhostColor,
    this.fade = const Duration(milliseconds: 150),
    this.minVisible = const Duration(milliseconds: 250),
  });

  final ui.Color color;
  final Duration fade;
  final Duration minVisible;

  VsbDocument? _document;
  List<String> _expectedIds = const [];
  final Map<int, _Entry> _entries = {};
  final Stopwatch _clock = Stopwatch()..start();
  Ticker? _ticker;

  /// Instante presente (para teste, sobrescreva com um relógio simulado).
  @visibleForTesting
  Duration Function()? nowOverride;
  Duration get _now => nowOverride?.call() ?? _clock.elapsed;

  void attachDocument(VsbDocument document) {
    if (identical(_document, document)) return;
    _document = document;
    clear();
    // Outra gravura: as colunas e páginas da revisão mudaram, refaz.
    if (_reviewRequests.isNotEmpty) {
      _computeReview();
      notifyListeners();
    }
  }

  /// Fantasmas a desenhar agora, com opacidade.
  List<VisibleGhost> get visible => [
    for (final e in _entries.values)
      if (e.ghost case final g?) VisibleGhost(g, e.opacity),
    for (final g in _review) VisibleGhost(g, 1),
  ];

  bool get isEmpty => _entries.isEmpty && _review.isEmpty;

  List<GhostRequest> _reviewRequests = const [];
  List<GhostNote> _review = const [];

  /// As fantasmas fixas da revisão (na ordem em que foram pedidas, as que
  /// não acharam coluna ficam de fora). Não somem com [clear] nem com o
  /// fade: só [clearReview] (ou um documento novo) as tira.
  List<GhostNote> get review => _review;

  /// Mostra [requests] fixas na partitura, no lugar das da revisão anterior.
  /// Pedidos iguais (mesma tecla, coluna e lado) valem um só.
  void setReview(Iterable<GhostRequest> requests) {
    final seen = <String>{};
    _reviewRequests = [
      for (final r in requests)
        if (seen.add('${r.key}|${r.side}|${r.targetIds.join(',')}')) r,
    ];
    _computeReview();
    notifyListeners();
  }

  void clearReview() {
    if (_reviewRequests.isEmpty && _review.isEmpty) return;
    _reviewRequests = const [];
    _review = const [];
    notifyListeners();
  }

  void _computeReview() {
    final doc = _document;
    if (doc == null || doc.pitchPos == null) {
      _review = const [];
      return;
    }
    final groups = <String, List<GhostRequest>>{};
    for (final r in _reviewRequests) {
      (groups['${r.side}|${r.targetIds.join(',')}'] ??= []).add(r);
    }
    _review = [
      for (final group in groups.values)
        ..._placed(doc, group.first.targetIds, group.first.side, [
          for (final r in group) r.key,
        ]),
    ];
  }

  List<GhostNote> _placed(
    VsbDocument doc,
    List<String> targetIds,
    int side,
    List<int> keys,
  ) => [
    for (final g in doc.ghostsFor(expectedIds: targetIds, wrongKeys: keys))
      g.shifted(side * g.headWidth * kGhostSideOffsetHeads),
  ];

  /// Ids do(s) evento(s) esperado(s) no instante — **todas** as notas do
  /// acorde (ids do timemap servem; `sceneIdOf` resolve `-rend<N>`). Muda
  /// quando o passo do treino avança; as fantasmas apertadas migram de coluna.
  void setExpected(List<String> ids) {
    if (listEquals(ids, _expectedIds)) return;
    _expectedIds = List.of(ids);
    _recompute();
  }

  /// Tecla errada apertada. Sem [targetIds] a fantasma vai para a coluna do
  /// evento esperado de [setExpected] (modo espera); com eles, para a coluna
  /// dos eventos indicados, deslocada para a esquerda ([side] `-1`, tocada
  /// antes do tempo) ou para a direita (`1`, depois) — o tempo real.
  void press(int key, {List<String>? targetIds, int side = 0}) {
    final old = _entries[key];
    if (old != null && old.releaseAt == null) return;
    _entries.remove(key);
    _entries[key] = _Entry(_now, targetIds: targetIds, side: side);
    _recompute();
  }

  /// Tecla solta: fade curto depois do tempo mínimo na tela.
  void release(int key) {
    final e = _entries[key];
    if (e == null || e.releaseAt != null) return;
    final earliest = e.pressedAt + minVisible;
    final now = _now;
    e.releaseAt = earliest > now ? earliest : now;
    _ensureTicker();
    _tick();
  }

  /// Some com tudo de uma vez (fim de sessão, troca de documento).
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _stopTicker();
    notifyListeners();
  }

  void _recompute() {
    final doc = _document;
    final active = [
      for (final e in _entries.entries)
        if (e.value.releaseAt == null) e.key,
    ];
    if (doc != null && active.isNotEmpty) {
      if (doc.pitchPos == null) {
        // Sem pitchpos.json no .vsb (nativo anterior a G04): nenhuma
        // fantasma é calculável. Log em vez de silêncio — ver Y01.
        debugPrint(
          'fantasma: sem pitchpos.json no .vsb, ${active.length} tecla(s) '
          'sem fantasma',
        );
        for (final key in active) {
          _entries.remove(key);
        }
      } else {
        // Uma coluna e um lado por vez: as fantasmas da mesma coluna se
        // desviam umas das outras (D-FANT-COLISAO).
        final groups = <String, List<int>>{};
        for (final key in active) {
          final entry = _entries[key]!;
          final ids = entry.targetIds ?? _expectedIds;
          (groups['${entry.side}|${ids.join(',')}'] ??= []).add(key);
        }
        final byKey = <int, GhostNote>{};
        for (final keys in groups.values) {
          final entry = _entries[keys.first]!;
          for (final g in _placed(
            doc,
            entry.targetIds ?? _expectedIds,
            entry.side,
            keys,
          )) {
            byKey[g.key] = g;
          }
        }
        for (final key in active) {
          final g = byKey[key];
          if (g == null) {
            debugPrint('fantasma: sem candidato para a tecla $key');
            _entries.remove(key); // sem candidato: sem fantasma
          } else {
            _entries[key]!.ghost = g;
          }
        }
      }
    } else {
      for (final key in active) {
        _entries.remove(key);
      }
    }
    notifyListeners();
  }

  void _ensureTicker() {
    _ticker ??= _OwnTickerProvider().createTicker((_) => _tick());
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _stopTicker() {
    _ticker?.stop();
  }

  @visibleForTesting
  void tickForTest() => _tick();

  void _tick() {
    final now = _now;
    var fading = false;
    _entries.removeWhere((_, e) {
      final at = e.releaseAt;
      if (at == null) return false;
      if (now <= at) {
        fading = true;
        return false;
      }
      final t = (now - at).inMicroseconds / fade.inMicroseconds;
      if (t >= 1) return true;
      e.opacity = 1 - t;
      fading = true;
      return false;
    });
    if (!fading) _stopTicker();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Pinta as fantasmas de [page] no espaço de conteúdo (o mesmo do
/// `ScorePageView`: escala de pixels + `applyPageTransform`).
class GhostPainter extends CustomPainter {
  GhostPainter({
    required this.controller,
    required this.page,
    required this.pageRef,
    required this.glyphCache,
    required this.applyPageTransform,
  }) : super(repaint: controller);

  final GhostController controller;
  final ScenePage page;
  final PageRef pageRef;
  final GlyphCache glyphCache;
  final void Function(ui.Canvas) applyPageTransform;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final ghosts = [
      for (final v in controller.visible)
        if (v.ghost.page == pageRef) v,
    ];
    if (ghosts.isEmpty) return;
    canvas.save();
    final scale = size.width / page.widthPx;
    if (scale != 1.0) canvas.scale(scale);
    applyPageTransform(canvas);
    for (final v in ghosts) {
      final color = controller.color.withValues(
        alpha: controller.color.a * v.opacity,
      );
      final g = v.ghost;
      final line = ui.Paint()
        ..color = color
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.butt;
      for (final l in g.ledgers) {
        line.strokeWidth = l.thickness;
        canvas.drawLine(ui.Offset(l.x1, l.y), ui.Offset(l.x2, l.y), line);
      }
      final fill = ui.Paint()
        ..color = color
        ..style = ui.PaintingStyle.fill
        ..isAntiAlias = true;
      _glyph(canvas, g.head, fill);
      if (g.accidental case final a?) _glyph(canvas, a, fill);
      if (g.octaveMarker case final o?) _glyph(canvas, o, fill);
    }
    canvas.restore();
  }

  void _glyph(ui.Canvas canvas, GhostGlyph glyph, ui.Paint fill) {
    canvas.save();
    canvas.translate(glyph.x, glyph.y);
    canvas.scale(glyph.sx, glyph.sy);
    canvas.drawPath(glyphCache.pathFor(glyph.glyphId), fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GhostPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.page != page ||
      oldDelegate.pageRef != pageRef;
}

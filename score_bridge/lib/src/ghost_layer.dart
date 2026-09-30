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
  _Entry(this.pressedAt);
  GhostNote? ghost;
  final Duration pressedAt;
  Duration? releaseAt;
  double opacity = 1;
}

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
  }

  /// Fantasmas a desenhar agora, com opacidade.
  List<VisibleGhost> get visible => [
    for (final e in _entries.values)
      if (e.ghost case final g?) VisibleGhost(g, e.opacity),
  ];

  bool get isEmpty => _entries.isEmpty;

  /// Ids do(s) evento(s) esperado(s) no instante — **todas** as notas do
  /// acorde (ids do timemap servem; `sceneIdOf` resolve `-rend<N>`). Muda
  /// quando o passo do treino avança; as fantasmas apertadas migram de coluna.
  void setExpected(List<String> ids) {
    if (listEquals(ids, _expectedIds)) return;
    _expectedIds = List.of(ids);
    _recompute();
  }

  /// Tecla errada apertada.
  void press(int key) {
    final old = _entries[key];
    if (old != null && old.releaseAt == null) return;
    _entries.remove(key);
    _entries[key] = _Entry(_now);
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
        final byKey = {
          for (final g in doc.ghostsFor(
            expectedIds: _expectedIds,
            wrongKeys: active,
          ))
            g.key: g,
        };
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

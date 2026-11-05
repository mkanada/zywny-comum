// Camada da pausa substituta (L03): estado das pausas na tela (uma por coluna
// escondida, na cor de repouso do host, com "piscar" por coluna) e o painter
// que as desenha por cima da página. O cálculo é stand_in.dart; aqui só ciclo
// de vida, cor e pintura. Mesmo molde da camada da nota fantasma
// (ghost_layer.dart).
library;

import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter/scheduler.dart';

import 'glyph_cache.dart';
import 'model.dart';
import 'stand_in.dart';

/// Uma pausa na tela, com a cor do instante (a de repouso ou a do piscar).
class VisibleStandIn {
  const VisibleStandIn(this.key, this.rest, this.color);

  /// A chave da coluna, a mesma de [StandInController.setColumns].
  final Object key;
  final StandInRest rest;
  final ui.Color color;
}

class _Flash {
  _Flash({
    required this.color,
    required this.attack,
    required this.hold,
    required this.release,
    required this.curve,
    required this.start,
  });

  final ui.Color color;
  final Duration attack;
  final Duration hold;
  final Duration release;
  final Curve curve;
  final Duration start;
}

class _OwnTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'StandInController');
}

/// Dono das pausas substitutas. O host diz **quais colunas** estão escondidas
/// ([setColumns], cada uma com as notas dela); o controller calcula a pausa de
/// cada uma (`VsbDocument.standInFor`) e a mantém na cor de repouso
/// ([restColor]). [flash] pisca uma coluna (cor, ataque, sustentação,
/// soltura), nos moldes de `ScoreController.highlight`, e volta ao repouso.
///
/// Uma coluna sem pausa calculável (`.vsb` antigo, figura desconhecida, pauta
/// que não tem 5 linhas) fica de fora de [visible], sem exceção.
class StandInController extends ChangeNotifier {
  StandInController({required this.restColor});

  /// A cor de repouso das pausas (o app passa `kMemoRestColor`).
  final ui.Color restColor;

  VsbDocument? _document;
  Map<Object, List<String>> _columns = const {};
  final Map<Object, StandInRest?> _rests = {};
  final Map<Object, _Flash> _flashes = {};
  final Stopwatch _clock = Stopwatch()..start();
  Ticker? _ticker;

  /// Instante presente (para teste, sobrescreva com um relógio simulado).
  @visibleForTesting
  Duration Function()? nowOverride;
  Duration get _now => nowOverride?.call() ?? _clock.elapsed;

  /// Associa o documento cujas colunas viram pausa. O `ScorePageView` faz
  /// sozinho. Outro documento refaz as pausas.
  void attachDocument(VsbDocument document) {
    if (identical(_document, document)) return;
    _document = document;
    _flashes.clear();
    _stopTicker();
    if (_columns.isNotEmpty) {
      _compute();
      notifyListeners();
    }
  }

  /// As colunas escondidas agora, por chave do host, no lugar das de antes.
  /// Uma coluna que continua (mesma chave) mantém o piscar em curso; as
  /// outras somem. As notas de cada coluna são ids notados de uma pauta de
  /// desenho; ids expandidos valem.
  void setColumns(Map<Object, List<String>> columns) {
    _columns = {
      for (final e in columns.entries) e.key: List.unmodifiable(e.value),
    };
    _flashes.removeWhere((key, _) => !_columns.containsKey(key));
    _compute();
    notifyListeners();
  }

  /// Tira a pausa da coluna [key] (ela foi revelada). Sem efeito se não
  /// existe.
  void remove(Object key) {
    if (!_columns.containsKey(key)) return;
    _columns = {
      for (final e in _columns.entries)
        if (e.key != key) e.key: e.value,
    };
    _rests.remove(key);
    _flashes.remove(key);
    if (_flashes.isEmpty) _stopTicker();
    notifyListeners();
  }

  /// Tira todas as pausas.
  void clear() {
    if (_columns.isEmpty) return;
    _columns = const {};
    _rests.clear();
    _flashes.clear();
    _stopTicker();
    notifyListeners();
  }

  /// Pisca a pausa de [key]: `attack` até [color], `hold`, e `release` de
  /// volta à cor de repouso. Sem parâmetros é uma cor instantânea que se
  /// apaga em 300 ms com `easeOut`. Numa pausa já piscando, reinicia só a
  /// dela. Chave que não existe é ignorada.
  void flash(
    Object key,
    ui.Color color, {
    Duration attack = Duration.zero,
    Duration hold = Duration.zero,
    Duration release = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) {
    if (!_columns.containsKey(key)) return;
    _flashes[key] = _Flash(
      color: color,
      attack: attack,
      hold: hold,
      release: release,
      curve: curve,
      start: _now,
    );
    _ensureTicker();
    notifyListeners();
  }

  /// As chaves das colunas que existem agora (com ou sem pausa calculável).
  Iterable<Object> get keys => _columns.keys;

  /// A pausa de [key] (`null` se a coluna não existe ou não tem pausa).
  StandInRest? restOf(Object key) => _rests[key];

  /// A cor de [key] agora: a de repouso, ou a do piscar em curso.
  ui.Color colorOf(Object key) => _colorAt(key, _now);

  /// Há algum piscar em curso.
  bool get isFlashing => _flashes.isNotEmpty;

  /// As pausas a desenhar agora, com a cor do instante.
  List<VisibleStandIn> get visible {
    final now = _now;
    return [
      for (final e in _rests.entries)
        if (e.value case final rest?)
          VisibleStandIn(e.key, rest, _colorAt(e.key, now)),
    ];
  }

  bool get isEmpty => _rests.values.every((r) => r == null);

  ui.Color _colorAt(Object key, Duration now) {
    final flash = _flashes[key];
    if (flash == null) return restColor;
    final elapsed = now - flash.start;
    if (elapsed < flash.attack) {
      final t = elapsed.inMicroseconds / flash.attack.inMicroseconds;
      return ui.Color.lerp(restColor, flash.color, flash.curve.transform(t))!;
    }
    final afterHold = elapsed - flash.attack - flash.hold;
    if (afterHold <= Duration.zero) return flash.color;
    if (afterHold >= flash.release) return restColor;
    final t = afterHold.inMicroseconds / flash.release.inMicroseconds;
    return ui.Color.lerp(flash.color, restColor, flash.curve.transform(t))!;
  }

  void _compute() {
    final doc = _document;
    _rests.clear();
    if (doc == null) return;
    for (final e in _columns.entries) {
      final rest = doc.standInFor(e.value);
      if (rest == null) {
        debugPrint(
          'pausa substituta: sem pausa para a coluna ${e.key} '
          '(.vsb sem figura, pauta fora do padrão ou ids fora da cena)',
        );
      }
      _rests[e.key] = rest;
    }
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
    _flashes.removeWhere((_, f) {
      final end = f.start + f.attack + f.hold + f.release;
      return now >= end;
    });
    if (_flashes.isEmpty) _stopTicker();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Pinta as pausas substitutas de [page] no espaço de conteúdo (o mesmo do
/// `ScorePageView`: escala de pixels + `applyPageTransform`).
class StandInPainter extends CustomPainter {
  StandInPainter({
    required this.controller,
    required this.page,
    required this.pageRef,
    required this.glyphCache,
    required this.applyPageTransform,
  }) : super(repaint: controller);

  final StandInController controller;
  final ScenePage page;
  final PageRef pageRef;
  final GlyphCache glyphCache;
  final void Function(ui.Canvas) applyPageTransform;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final rests = [
      for (final v in controller.visible)
        if (v.rest.page == pageRef) v,
    ];
    if (rests.isEmpty) return;
    canvas.save();
    final scale = size.width / page.widthPx;
    if (scale != 1.0) canvas.scale(scale);
    applyPageTransform(canvas);
    for (final v in rests) {
      final fill = ui.Paint()
        ..color = v.color
        ..style = ui.PaintingStyle.fill
        ..isAntiAlias = true;
      final rest = v.rest;
      canvas.save();
      canvas.translate(rest.x, rest.y);
      canvas.scale(rest.sx, rest.sy);
      canvas.drawPath(glyphCache.pathFor(rest.glyphId), fill);
      canvas.restore();
      for (final dot in rest.dots) {
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: ui.Offset(dot.cx, dot.cy),
            width: dot.rx * 2,
            height: dot.ry * 2,
          ),
          fill,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StandInPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.page != page ||
      oldDelegate.pageRef != pageRef;
}

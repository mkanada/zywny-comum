// Motor de animação de destaque (A02a): N notas, cada uma na sua fase.
//
// Sem `Ticker`, sem widget, sem `DateTime.now()`: o tempo é sempre um
// argumento (`Duration` desde uma origem qualquer do chamador), o que torna o
// motor determinístico e testável com tempo simulado. Quem dirige o relógio
// é o `ScoreController`.
//
// Cada nota tem o próprio estado `{início, fases, cor, curva}` num mapa
// `id -> estado`. Não há agrupamento por instante: iniciar (ou reiniciar) uma
// nota não toca nas outras — o que o projeto anterior (Lottie) não permitia.
//
// Fases de uma nota (durações zero são válidas):
//   attack : base  -> cor        (com a curva)
//   hold   : cor constante
//   release: cor   -> base       (com a curva)
//
// INTERPOLAÇÃO: `Color.lerp`, em sRGB direto, por canal — o mesmo cálculo
// que os testes fazem à mão. A curva é aplicada ao **parâmetro** `t` da fase
// (`lerp(a, b, curve(t))`), nunca ao resultado.
library;

import 'dart:ui' as ui;

import 'package:flutter/animation.dart';

/// Parâmetros de um destaque.
class HighlightSpec {
  const HighlightSpec({
    required this.color,
    required this.baseColor,
    this.attack = Duration.zero,
    this.hold = Duration.zero,
    this.release = const Duration(milliseconds: 300),
    this.curve = Curves.easeOut,
  });

  /// A cor de destaque (a de `hold`).
  final ui.Color color;

  /// A cor de repouso do nó: a original resolvida da cena (com `@color` do
  /// MEI, se houver), ou a cor "fixa" que o host definiu. É a origem do
  /// `attack` e o destino do `release`.
  final ui.Color baseColor;

  final Duration attack;
  final Duration hold;
  final Duration release;
  final Curve curve;
}

class _Entry {
  _Entry(this.start, HighlightSpec spec)
    : color = spec.color,
      base = spec.baseColor,
      attackUs = spec.attack.inMicroseconds,
      curve = spec.curve {
    releaseStart = start + spec.attack + spec.hold;
    releaseUs = spec.release.inMicroseconds;
    releaseCurve = spec.curve;
  }

  final Duration start;
  final ui.Color color;
  ui.Color base;
  final int attackUs;
  final Curve curve;

  /// Início e duração do `release`; um `stop` antecipado os substitui.
  late Duration releaseStart;
  late int releaseUs;
  late Curve releaseCurve;

  /// Cor de partida do `release` — `null` é a cor de destaque (release
  /// natural); num `stop` antecipado é a cor do instante do `stop`.
  ui.Color? releaseFrom;

  /// Intensidade do halo em [now] (0–1: some fora da janela ativa), na mesma
  /// fase de [colorAt] mas sem se misturar com [base] — o halo é sempre na
  /// cor de destaque, só a força dele sobe no `attack` e desce no `release`.
  double _haloIntensity(Duration now) {
    final elapsed = (now - start).inMicroseconds;
    if (elapsed < 0) {
      return 0;
    }
    if (now < releaseStart) {
      return elapsed < attackUs ? curve.transform(elapsed / attackUs) : 1.0;
    }
    final into = (now - releaseStart).inMicroseconds;
    if (into >= releaseUs) {
      return 0;
    }
    return 1.0 - releaseCurve.transform(into / releaseUs);
  }

  /// Cor do halo em [now]: [color] com a intensidade acima como alfa; `null`
  /// fora da janela ativa.
  ui.Color? haloAt(Duration now) {
    final intensity = _haloIntensity(now);
    if (intensity <= 0) {
      return null;
    }
    return color.withValues(alpha: color.a * intensity);
  }

  /// Cor da nota em [now]; `null` quando a animação já terminou.
  ui.Color? colorAt(Duration now) {
    final elapsed = (now - start).inMicroseconds;
    if (elapsed < 0) {
      return base;
    }
    if (now < releaseStart) {
      if (elapsed < attackUs) {
        return ui.Color.lerp(base, color, curve.transform(elapsed / attackUs));
      }
      return color;
    }
    final into = (now - releaseStart).inMicroseconds;
    if (into >= releaseUs) {
      return null;
    }
    return ui.Color.lerp(
      releaseFrom ?? color,
      base,
      releaseCurve.transform(into / releaseUs),
    );
  }
}

/// Estado de todas as notas acesas e o cálculo da cor de cada uma.
class HighlightEngine {
  final Map<String, _Entry> _entries = {};

  // Resultado reaproveitado entre chamadas de `colorsAt`: nada é alocado por
  // frame além dos `Color` interpolados.
  final Map<String, ui.Color> _colors = {};
  final List<String> _finished = [];
  final List<String> _pendingRemoval = [];
  final Map<String, ui.Color> _halos = {};

  /// Nenhuma nota ativa: o dono do relógio pode parar o `Ticker`.
  bool get isIdle => _entries.isEmpty;

  /// Quantas notas estão acesas (em qualquer fase).
  int get activeCount => _entries.length;

  bool isActive(String id) => _entries.containsKey(id);

  /// Os ids acesos (em qualquer fase). Visão viva: não modifique o motor
  /// enquanto itera.
  Iterable<String> get activeIds => _entries.keys;

  /// Acende [id] em [now]. Se já estava acesa, **reinicia** a própria
  /// animação (do início do `attack`) sem tocar em nenhuma outra.
  void start(String id, HighlightSpec spec, Duration now) {
    _entries[id] = _Entry(now, spec);
  }

  /// Antecipa o `release` de [id] para [at], a partir da cor que ela tem
  /// nesse instante (sem salto). [release] e [curve] substituem os do
  /// destaque. Se a nota já está em `release` desde antes de [at], o
  /// `release` em andamento é mantido. Id que não está ativo é ignorado.
  ///
  /// Diferença do esboço do plano: [at] é posicional e obrigatório — o motor
  /// não tem relógio, então "agora" tem que vir de fora.
  void stop(String id, Duration at, {Duration? release, Curve? curve}) {
    final entry = _entries[id];
    if (entry == null || at >= entry.releaseStart) {
      return;
    }
    final from = entry.colorAt(at) ?? entry.base;
    entry.releaseFrom = from;
    entry.releaseStart = at;
    if (release != null) {
      entry.releaseUs = release.inMicroseconds;
    }
    if (curve != null) {
      entry.releaseCurve = curve;
    }
  }

  /// [stop] em todas as notas ativas.
  void stopAll(Duration at, {Duration? release, Curve? curve}) {
    for (final id in _entries.keys.toList()) {
      stop(id, at, release: release, curve: curve);
    }
  }

  /// Muda a cor de repouso de [id] enquanto ela anima (o `setColor` do
  /// controller). Id que não está ativo é ignorado.
  void rebase(String id, ui.Color base) => _entries[id]?.base = base;

  /// Apaga tudo **agora**, sem fade.
  void clear() {
    _entries.clear();
    _colors.clear();
    _pendingRemoval.clear();
    _halos.clear();
  }

  /// Cor de cada nota ativa em [now], só das ativas.
  ///
  /// O mapa devolvido é **reaproveitado**: vale até a próxima chamada e não
  /// deve ser modificado nem guardado. Uma nota cujo `release` termina é
  /// devolvida uma última vez com **exatamente** a `baseColor`, e sai do
  /// motor (e do mapa) na chamada seguinte.
  Map<String, ui.Color> colorsAt(Duration now) {
    for (final id in _pendingRemoval) {
      _colors.remove(id);
    }
    _pendingRemoval.clear();
    for (final entry in _entries.entries) {
      final color = entry.value.colorAt(now);
      if (color == null) {
        _colors[entry.key] = entry.value.base;
        _finished.add(entry.key);
      } else {
        _colors[entry.key] = color;
      }
    }
    if (_finished.isNotEmpty) {
      for (final id in _finished) {
        _entries.remove(id);
        _pendingRemoval.add(id);
      }
      _finished.clear();
    }
    return _colors;
  }

  /// Cor do halo (a de destaque, com o alfa subindo no `attack` e caindo no
  /// `release` — nunca misturada com [_Entry.base]) de cada nota com halo
  /// visível em [now]. Ids fora da janela ativa não aparecem. Chame depois
  /// de [colorsAt] no mesmo [now], para refletir as notas já concluídas.
  Map<String, ui.Color> haloColorsAt(Duration now) {
    _halos.clear();
    for (final entry in _entries.entries) {
      final color = entry.value.haloAt(now);
      if (color != null) {
        _halos[entry.key] = color;
      }
    }
    return _halos;
  }
}

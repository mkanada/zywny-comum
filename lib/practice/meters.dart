// EX07: os nove medidores. Cada um é uma função pura de [MeterInput] (o
// escrito, a gravação, o casamento e as marcas) que devolve um [MeterResult].
// Sem dado para medir, o valor é `NaN` e o medidor não reprova. Os alvos vêm
// do `pass` do autor (EX08); só a % da dinâmica é fixa (kDynamicsTarget). Os
// limiares de legato, staccato e pedal seguem os provisórios do EX07
// (D-EXE-LIMIARES, ainda aberta: a calibração com o teclado é manual). Os ms
// de parede são os musicais divididos pelo andamento, como no PracticeReport.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:zywny_audio/performance_track.dart';

import 'expression_marks.dart';
import 'meter_result.dart';
import 'performance_capture.dart';
import 'practice_report.dart';

export 'meter_result.dart';

/// Limiares provisórios (EX07, tabela).
const double kLegatoHoleMs = -20;
const double kLegatoBlurMs = 80;
const double kLegatoBlurShare = 0.25;
const double kStaccatoShare = 0.6;
const double kDynamicsStepVelocity = 12;
const double kPedalSmearBeforeMs = 30;
const double kPedalSmearAfterMs = 250;
const double kPedalGapAfterMs = 400;

/// Duas notas são "a mesma nota" (um pedal que chega com o acorde, um compasso
/// que começa) quando os ataques distam menos de isto, em ms musicais.
const double kSameInstantMs = 1;

/// Sem pausa entre duas notas seguidas (o fim de uma é o começo da outra).
const double kNoRestMs = 1;

/// Os dados que os medidores leem. [matches] é o que a conferência casou;
/// [track] e [staves] dizem o escrito que o aluno toca; [capture] é a
/// gravação inteira (para o pedal e as velocities).
@immutable
class MeterInput {
  const MeterInput({
    required this.track,
    required this.staves,
    required this.capture,
    required this.matches,
    this.marks = ExpressionMarks.empty,
    this.speed = 1,
    this.measureAt,
    this.legatoRequested = false,
    this.pedalRequested = false,
    this.harmonyChangesMs = const [],
    this.beatsMs = const [],
    this.report,
    this.chorusStarts = const [],
    this.roundDone = false,
  }) : assert(speed > 0);

  final PerformanceTrack track;
  final Set<int> staves;
  final PerformanceCapture capture;
  final List<MatchedNote> matches;
  final ExpressionMarks marks;

  /// Andamento da sessão: os ms de parede são os musicais divididos por ele.
  final double speed;

  /// Compasso (ocorrência, índice de `ScoreTimeline.measures`) de um ms
  /// musical. `null`: tudo cai no compasso 0.
  final int Function(double ms)? measureAt;

  /// O `pass` pede legato: sem ligadura de expressão, vale o par seguido.
  final bool legatoRequested;

  /// O `pass` pede pedal.
  final bool pedalRequested;

  /// Instantes (ms musicais) das trocas de harmonia. Vazio: as do pedal
  /// escrito no arquivo.
  final List<double> harmonyChangesMs;

  /// Inícios dos tempos (ms musicais) para o swing: cada tempo vai do seu
  /// início ao seguinte.
  final List<double> beatsMs;

  /// O resumo da rodada, com os erros de cada compasso (para as voltas).
  final PracticeReport? report;

  /// Compasso (ocorrência) em que cada volta da forma começa.
  final List<int> chorusStarts;

  /// A rodada acabou: a última volta conta como completa.
  final bool roundDone;
}

/// Os nove medidores, na ordem da tabela do EX07. [targets] dá o alvo de cada
/// um pelo id, e [swing] a faixa da razão; sem alvo, o medidor mostra o número
/// e não reprova.
List<MeterResult> allMeters(
  MeterInput input, {
  Map<String, double> targets = const {},
  (int, int)? swing,
}) => [
  meterLegato(input, target: targets['legato']),
  meterStaccato(input, target: targets['staccato']),
  meterDynamics(input, target: targets['dynamics']),
  meterBalance(input, target: targets['balance']),
  meterPedal(input, target: targets['pedal']),
  meterSteadiness(input, target: targets['steadiness']),
  meterSwing(input, range: swing),
  meterAccents(input, target: targets['accents']),
  meterChoruses(input, target: targets['choruses']),
];

/// Legato: a sobreposição `s = off(a) − on(b)` de cada par de notas seguidas
/// da mesma pauta que a partitura liga. Buraco se `s` passa de −20 ms, borrão
/// se passa de `max(80 ms, 25% da duração escrita de a)`. Passa o percentual
/// de ligações limpas.
MeterResult meterLegato(MeterInput input, {double? target}) {
  const id = 'legato';
  final byKey = _matchesByKey(input.matches);
  var total = 0, holes = 0, blurs = 0;
  final measures = <int>{};
  for (final (a, b) in _legatoPairs(input)) {
    final ma = byKey[_keyOf(a)], mb = byKey[_keyOf(b)];
    final endA = ma?.played.offMs;
    if (ma == null || mb == null || endA == null) continue;
    total++;
    final overlap = (endA - mb.played.onMs) / input.speed;
    final blurLimit = math.max(
      kLegatoBlurMs,
      kLegatoBlurShare * (a.offMs - a.onMs) / input.speed,
    );
    if (overlap < kLegatoHoleMs) {
      holes++;
      measures.add(_measureOf(input, b.onMs));
    } else if (overlap > blurLimit) {
      blurs++;
      measures.add(_measureOf(input, b.onMs));
    }
  }
  if (total == 0) return _nothing(id);
  final clean = total - holes - blurs;
  final list = _sorted(measures);
  return _judged(
    id,
    clean * 100 / total,
    '$clean de $total ligações limpas'
    '${holes > 0 ? '; $holes com buraco' : ''}'
    '${blurs > 0 ? '; $blurs borradas' : ''}'
    '${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Staccato: a nota marcada tem de soar no máximo 60% da duração escrita.
/// Passa o percentual de notas curtas. Sem marcas de staccato, nada a medir.
MeterResult meterStaccato(MeterInput input, {double? target}) {
  const id = 'staccato';
  var total = 0, short = 0;
  final measures = <int>{};
  for (final m in input.matches) {
    if (!input.marks.staccato.contains(m.written.id)) continue;
    final endPlayed = m.played.offMs;
    final written = m.written.offMs - m.written.onMs;
    if (endPlayed == null || written <= 0) continue;
    total++;
    if (endPlayed - m.played.onMs <= kStaccatoShare * written) {
      short++;
    } else {
      measures.add(_measureOf(input, m.written.onMs));
    }
  }
  if (total == 0) return _nothing(id);
  final list = _sorted(measures);
  final long = total - short;
  return _judged(
    id,
    short * 100 / total,
    '$short de $total staccatos soaram curtos'
    '${long > 0 ? '; $long soaram longos' : ''}${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Dinâmica: a velocity mediana de cada trecho de dinâmica escrita. Entre dois
/// trechos vizinhos de marca diferente, a ordem tem de seguir a das marcas e a
/// diferença ter pelo menos 12. No crescendo e no diminuendo, a inclinação da
/// velocity no trecho tem de ter o sinal certo. Passa o percentual de trechos
/// certos.
MeterResult meterDynamics(MeterInput input, {double? target}) {
  const id = 'dynamics';
  if (input.matches.isEmpty) return _nothing(id);
  if (_keyboardSilent(input)) return _silentKeyboard(id);
  var checked = 0, right = 0;
  final measures = <int>{};

  final marks = [...input.marks.dynamics]
    ..sort((a, b) => a.atMs.compareTo(b.atMs));
  final wedges = input.marks.wedges;
  ({double median, DynamicLevel level})? previous;
  for (var i = 0; i < marks.length; i++) {
    final from = marks[i].atMs;
    final to = i + 1 < marks.length ? marks[i + 1].atMs : double.infinity;
    final notes = [
      for (final m in input.matches)
        if (m.written.onMs >= from &&
            m.written.onMs < to &&
            !_inWedge(wedges, m.written.onMs))
          m,
    ];
    if (notes.isEmpty) continue;
    final median = _median(_velocities(notes));
    final level = marks[i].level;
    final before = previous;
    if (before != null && before.level != level) {
      checked++;
      final diff = median - before.median;
      final rightWay = level.index > before.level.index ? diff > 0 : diff < 0;
      if (rightWay && diff.abs() >= kDynamicsStepVelocity) {
        right++;
      } else {
        measures.add(_measureOf(input, from));
      }
    }
    previous = (median: median, level: level);
  }

  for (final wedge in wedges) {
    final points = [
      for (final m in input.matches)
        if (m.written.onMs >= wedge.startMs && m.written.onMs < wedge.endMs) m,
    ];
    if (points.length < 2) continue;
    final slope = _slope(points);
    if (slope.isNaN) continue;
    checked++;
    if (wedge.crescendo ? slope > 0 : slope < 0) {
      right++;
    } else {
      measures.add(_measureOf(input, wedge.startMs));
    }
  }

  if (checked == 0) return _nothing(id);
  final list = _sorted(measures);
  return _judged(
    id,
    right * 100 / checked,
    '$right de $checked trechos de dinâmica certos${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Equilíbrio: a velocity mediana da melodia menos a do acompanhamento, em cada
/// ataque simultâneo. A melodia é a pauta de cima quando o acorde passa de uma
/// pauta; dentro de uma pauta, a nota mais aguda. O valor é a mediana dessas
/// diferenças.
MeterResult meterBalance(MeterInput input, {double? target}) {
  const id = 'balance';
  if (input.matches.isEmpty) return _nothing(id);
  if (_keyboardSilent(input)) return _silentKeyboard(id);
  final diffs = <({double diff, int measure})>[];
  for (final chord in _groupByOnset(input.matches).values) {
    if (chord.length < 2) continue;
    final melody = _melodyOf(chord);
    final rest = [
      for (final m in chord)
        if (!melody.contains(m)) m,
    ];
    if (rest.isEmpty) continue;
    diffs.add((
      diff: _median(_velocities(melody)) - _median(_velocities(rest)),
      measure: _measureOf(input, chord.first.written.onMs),
    ));
  }
  if (diffs.isEmpty) return _nothing(id);
  final value = _median([for (final d in diffs) d.diff]);
  final list = _sorted({
    for (final d in diffs)
      if (d.diff < (target ?? 0)) d.measure,
  });
  final sentence = value >= 0
      ? 'a melodia sai ${value.round()} de força acima do acompanhamento'
      : 'o acompanhamento sai ${(-value).round()} acima da melodia';
  return _judged(
    id,
    value,
    '$sentence${target == null ? '' : ' (alvo ${target.round()})'}'
    '${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Pedal: em cada troca de harmonia, o pedal não pode ficar abaixado sem
/// subir entre `on − 30 ms` e `on + 250 ms` (borrão), nem ficar em cima sem
/// descer até `on + 400 ms` (buraco). `on` é o ataque tocado do acorde novo.
/// Sem pedal chegado do teclado, diz que ele está desligado (se o `pass` pede
/// pedal) ou não diz nada.
MeterResult meterPedal(MeterInput input, {double? target}) {
  const id = 'pedal';
  final pedals = input.capture.pedals;
  if (pedals.isEmpty) {
    return input.pedalRequested
        ? MeterResult(
            id: id,
            value: double.nan,
            sentence: 'nenhum pedal chegou do teclado; ele está ligado?',
          )
        : _nothing(id);
  }
  var total = 0, smears = 0, gaps = 0;
  final measures = <int>{};
  for (final change in _harmonyChanges(input)) {
    final on = _firstPlayedOnset(input, change);
    if (on == null) continue;
    total++;
    final before = on - kPedalSmearBeforeMs;
    final downBefore = _pedalDownAt(pedals, before);
    final lifted = pedals.any(
      (p) => !p.down && p.atMs > before && p.atMs <= on + kPedalSmearAfterMs,
    );
    final downAfter = pedals.any(
      (p) => p.down && p.atMs >= before && p.atMs <= on + kPedalGapAfterMs,
    );
    if (downBefore && !lifted) {
      smears++;
      measures.add(_measureOf(input, change));
    } else if (!downBefore && !downAfter) {
      gaps++;
      measures.add(_measureOf(input, change));
    }
  }
  if (total == 0) return _nothing(id);
  final list = _sorted(measures);
  return _judged(
    id,
    (total - smears - gaps) * 100 / total,
    '${total - smears - gaps} de $total trocas de pedal limpas'
    '${smears > 0 ? '; $smears borradas' : ''}'
    '${gaps > 0 ? '; $gaps com buraco' : ''}${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Regularidade: o desvio-padrão do atraso de cada nota casada (a conta do
/// PracticeReport), e a média, que diz se o aluno corre (negativa) ou arrasta
/// (positiva). Quanto menor, melhor.
MeterResult meterSteadiness(MeterInput input, {double? target}) {
  const id = 'steadiness';
  if (input.matches.isEmpty) return _nothing(id);
  final deltas = [
    for (final m in input.matches)
      (m.played.onMs - m.written.onMs) / input.speed,
  ];
  final sd = stdDevOf(deltas);
  final mean = deltas.reduce((a, b) => a + b) / deltas.length;
  final lean = mean.abs() < 1
      ? 'no tempo'
      : mean < 0
      ? 'corre ${mean.abs().round()} ms em média'
      : 'arrasta ${mean.round()} ms em média';
  return _judged(
    id,
    sd,
    'desvio de ${sd.round()} ms; $lean.',
    target: target,
    lowerIsBetter: true,
  );
}

/// Swing: em cada tempo com exatamente duas colcheias escritas, a posição da
/// segunda (`(on(2ª) − início do tempo) / duração do tempo`, em %). 50 é reto,
/// 67 é tercina. Passa a mediana; com [range] (`swing: 60-70`), a mediana tem
/// de cair dentro da faixa.
MeterResult meterSwing(MeterInput input, {(int, int)? range}) {
  const id = 'swing';
  final beats = input.beatsMs;
  final written = _writtenOf(input);
  final ratios = <double>[];
  for (var k = 0; k + 1 < beats.length; k++) {
    final start = beats[k], end = beats[k + 1];
    final onsets = _onsets([
      for (final e in written)
        if (e.onMs >= start && e.onMs < end) e,
    ]);
    if (onsets.length != 2) continue;
    final second = onsets[1].first.onMs;
    MatchedNote? played;
    for (final m in input.matches) {
      if ((m.written.onMs - second).abs() < kSameInstantMs) {
        played = m;
        break;
      }
    }
    if (played == null) continue;
    ratios.add((played.played.onMs - start) * 100 / (end - start));
  }
  if (ratios.isEmpty) return _nothing(id);
  final value = _median(ratios);
  final passed = range == null ? null : value >= range.$1 && value <= range.$2;
  return MeterResult(
    id: id,
    value: value,
    passed: passed,
    sentence:
        'a segunda colcheia cai em ${value.round()}% do tempo '
        '(50 = reto, 67 = tercina), em ${ratios.length} '
        '${ratios.length == 1 ? 'tempo' : 'tempos'}'
        '${range == null ? '' : ', e a faixa pedida é ${range.$1}-${range.$2}'}.',
  );
}

/// Acentos: a velocity mediana das notas acentuadas menos a das outras. Passa
/// a diferença.
MeterResult meterAccents(MeterInput input, {double? target}) {
  const id = 'accents';
  final accented = [
    for (final m in input.matches)
      if (input.marks.accents.contains(m.written.id)) m,
  ];
  final others = [
    for (final m in input.matches)
      if (!input.marks.accents.contains(m.written.id)) m,
  ];
  if (accented.isEmpty || others.isEmpty) return _nothing(id);
  if (_keyboardSilent(input)) return _silentKeyboard(id);
  final restMedian = _median(_velocities(others));
  final value = _median(_velocities(accented)) - restMedian;
  final list = _sorted({
    for (final m in accented)
      if (m.played.velocity - restMedian < (target ?? 0))
        _measureOf(input, m.written.onMs),
  });
  final sentence = value >= 0
      ? 'os acentos saem ${value.round()} de força acima do resto'
      : 'os acentos saem ${(-value).round()} mais fracos que o resto';
  return _judged(
    id,
    value,
    '$sentence${target == null ? '' : ' (alvo ${target.round()})'}'
    '${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

/// Voltas: a maior sequência de voltas completas da forma sem nenhuma nota
/// errada ou perdida. Uma volta é completa quando tem a seguinte, ou quando a
/// rodada acabou. Com [target] (`choruses: 2`), passa se chegar a ele.
MeterResult meterChoruses(MeterInput input, {double? target}) {
  const id = 'choruses';
  final report = input.report;
  final starts = input.chorusStarts;
  if (report == null || starts.isEmpty) return _nothing(id);
  final complete = input.roundDone ? starts.length : starts.length - 1;
  if (complete <= 0) return _nothing(id);

  var run = 0, best = 0;
  final measures = <int>{};
  for (var k = 0; k < complete; k++) {
    final from = starts[k];
    final to = k + 1 < starts.length ? starts[k + 1] : null;
    final errors = report.measures
        .where((m) => m.index >= from && (to == null || m.index < to))
        .fold(0, (sum, m) => sum + m.errors);
    if (errors > 0) {
      run = 0;
      measures.add(from);
    } else {
      run++;
      best = math.max(best, run);
    }
  }
  final list = _sorted(measures);
  return _judged(
    id,
    best.toDouble(),
    '$best ${best == 1 ? 'volta seguida' : 'voltas seguidas'} sem erro, '
    'de $complete completas${_atMeasures(list)}.',
    target: target,
    measures: list,
  );
}

// ---- o que os medidores compartilham -------------------------------------

typedef _Key = (String, int, double);

_Key _keyOf(SoundEvent e) => (e.id, e.pitch, e.onMs);

Map<_Key, MatchedNote> _matchesByKey(List<MatchedNote> matches) => {
  for (final m in matches) _keyOf(m.written): m,
};

/// As notas escritas que o aluno toca (das pautas dele, sem ornamento), na
/// ordem do escrito.
List<SoundEvent> _writtenOf(MeterInput input) => [
  for (final e in input.track.events)
    if (input.staves.contains(e.staff) && !e.ornament) e,
];

int _measureOf(MeterInput input, double ms) => input.measureAt?.call(ms) ?? 0;

MeterResult _nothing(String id) =>
    MeterResult(id: id, value: double.nan, sentence: 'nada para medir aqui');

/// Teclado que manda a mesma velocity para todas as teclas: não dá para medir
/// a força, e o medidor não reprova.
MeterResult _silentKeyboard(String id) => MeterResult(
  id: id,
  value: double.nan,
  sentence: 'seu teclado não manda a força da tecla',
);

bool _keyboardSilent(MeterInput input) {
  final notes = input.capture.notes;
  return notes.length >= 2 && notes.map((n) => n.velocity).toSet().length == 1;
}

MeterResult _judged(
  String id,
  double value,
  String sentence, {
  double? target,
  bool lowerIsBetter = false,
  List<int> measures = const [],
}) {
  final passed = target == null
      ? null
      : lowerIsBetter
      ? value <= target
      : value >= target;
  return MeterResult(
    id: id,
    value: value,
    target: target,
    passed: passed,
    sentence: sentence,
    measures: measures,
  );
}

String _atMeasures(List<int> measures) =>
    measures.isEmpty ? '' : ' (c. ${measures.map((m) => m + 1).join(', ')})';

List<int> _sorted(Iterable<int> values) => values.toSet().toList()..sort();

List<double> _velocities(Iterable<MatchedNote> notes) => [
  for (final m in notes) m.played.velocity.toDouble(),
];

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Os eventos agrupados pelo ataque, em ordem de tempo.
List<List<SoundEvent>> _onsets(Iterable<SoundEvent> events) {
  final byOn = <double, List<SoundEvent>>{};
  for (final e in events) {
    byOn.putIfAbsent(e.onMs, () => []).add(e);
  }
  final keys = byOn.keys.toList()..sort();
  return [for (final k in keys) byOn[k]!];
}

Map<double, List<MatchedNote>> _groupByOnset(List<MatchedNote> matches) {
  final byOn = <double, List<MatchedNote>>{};
  for (final m in matches) {
    byOn.putIfAbsent(m.written.onMs, () => []).add(m);
  }
  return byOn;
}

/// A melodia de um ataque simultâneo: a pauta de cima, se o acorde passa de
/// uma pauta; senão, a nota mais aguda.
List<MatchedNote> _melodyOf(List<MatchedNote> chord) {
  final staves = chord.map((m) => m.written.staff).toSet();
  if (staves.length > 1) {
    final top = staves.reduce(math.min);
    return [
      for (final m in chord)
        if (m.written.staff == top) m,
    ];
  }
  final high = chord.map((m) => m.written.pitch).reduce(math.max);
  return [
    for (final m in chord)
      if (m.written.pitch == high) m,
  ];
}

/// Os pares ligados: os das marcas, se há; senão, os seguidos da pauta (só se
/// o `pass` pediu legato).
List<(SoundEvent, SoundEvent)> _legatoPairs(MeterInput input) {
  final written = _writtenOf(input);
  if (input.marks.slurs.isNotEmpty) {
    final byId = <String, SoundEvent>{};
    for (final e in written) {
      byId.putIfAbsent(e.id, () => e);
    }
    return [
      for (final (a, b) in input.marks.slurs)
        if (byId[a] != null && byId[b] != null) (byId[a]!, byId[b]!),
    ];
  }
  if (!input.legatoRequested) return const [];
  final pairs = <(SoundEvent, SoundEvent)>[];
  final staves = written.map((e) => e.staff).toSet();
  for (final staff in staves) {
    final onsets = _onsets(written.where((e) => e.staff == staff));
    for (var i = 0; i + 1 < onsets.length; i++) {
      final a = onsets[i], b = onsets[i + 1];
      if (a.length != 1 || b.length != 1) continue;
      if (b.single.onMs - a.single.offMs > kNoRestMs) continue;
      pairs.add((a.single, b.single));
    }
  }
  return pairs;
}

/// A inclinação da velocity pelo tempo escrito (velocity por ms), por
/// mínimos quadrados. `NaN` se os ataques são todos no mesmo instante.
double _slope(List<MatchedNote> points) {
  final xs = [for (final m in points) m.written.onMs];
  final ys = _velocities(points);
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var cov = 0.0, varX = 0.0;
  for (var i = 0; i < xs.length; i++) {
    cov += (xs[i] - mx) * (ys[i] - my);
    varX += (xs[i] - mx) * (xs[i] - mx);
  }
  return varX == 0 ? double.nan : cov / varX;
}

bool _inWedge(List<WedgeMark> wedges, double ms) =>
    wedges.any((w) => ms >= w.startMs && ms < w.endMs);

/// As trocas de harmonia: as da entrada, ou as do pedal escrito (distintas).
List<double> _harmonyChanges(MeterInput input) {
  if (input.harmonyChangesMs.isNotEmpty) return input.harmonyChangesMs;
  final times = [for (final p in input.track.pedal) p.timeMs]..sort();
  final distinct = <double>[];
  for (final t in times) {
    if (distinct.isEmpty || t - distinct.last >= kSameInstantMs) {
      distinct.add(t);
    }
  }
  return distinct;
}

/// O ataque tocado do acorde de [change]: o primeiro das notas escritas nesse
/// instante que a conferência casou.
double? _firstPlayedOnset(MeterInput input, double change) {
  double? first;
  for (final m in input.matches) {
    if ((m.written.onMs - change).abs() >= kSameInstantMs) continue;
    if (first == null || m.played.onMs < first) first = m.played.onMs;
  }
  return first;
}

/// Se o pedal estava abaixado no instante [ms]: o último movimento até ele.
bool _pedalDownAt(List<CapturedPedal> pedals, double ms) {
  var down = false;
  for (final p in pedals) {
    if (p.atMs > ms) break;
    down = p.down;
  }
  return down;
}

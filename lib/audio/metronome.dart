// T04: batidas do metrônomo e da contagem inicial, derivadas do timemap do
// `.vsb` — que não traz fórmula de compasso, só `qstamp` (semínimas desde o
// início) e `measureOn` (abre a ocorrência de um compasso). Uma batida por
// semínima, a 1ª do compasso é o tempo forte. Em 6/8 (ou qualquer fórmula
// composta) isso dá batidas de semínima, não de colcheia pontuada — aceito
// para a 1.0 (T04, "fora de escopo": fórmulas compostas perfeitas).
//
// O `qstamp` só existe nas entradas do timemap, então o instante de uma
// semínima sem entrada (o tempo 2 de um compasso 3/4 com uma nota longa) sai
// por interpolação linear entre as entradas vizinhas do compasso; depois da
// última entrada, extrapola com a inclinação do último trecho.
import 'package:score_bridge/score_bridge.dart';

/// Uma batida do metrônomo, em ms musicais (o relógio de `PerformanceTrack`).
class Beat {
  const Beat(this.ms, {required this.accent, required this.measure});

  final double ms;

  /// Tempo forte (1ª batida do compasso).
  final bool accent;

  /// Índice em `ScoreTimeline.measures` (ocorrência, em ordem de execução).
  final int measure;

  @override
  String toString() =>
      'Beat(${ms.toStringAsFixed(1)}ms'
      '${accent ? ' >' : ''} c$measure)';
}

/// Nota GM de percussão (canal 9): "Hi Wood Block" no tempo forte, "Low Wood
/// Block" nos demais.
const int kMetronomeChannel = 9;
const int kMetronomeAccentNote = 76;
const int kMetronomeNote = 77;

/// Batidas de todos os compassos de [timeline], em ordem de execução.
List<Beat> metronomeBeats(ScoreTimeline timeline) {
  final beats = <Beat>[];
  final entries = timeline.entries;
  final measures = timeline.measures;
  var e = 0; // primeira entrada com tstamp >= startMs do compasso corrente
  for (var m = 0; m < measures.length; m++) {
    final info = measures[m];
    while (e < entries.length && entries[e].tstamp < info.startMs) {
      e++;
    }
    // Pontos (tstamp, qstamp) do compasso, incluindo a entrada que abre o
    // seguinte (tstamp == endMs) quando houver: é a âncora do fim.
    final pts = <(double, double)>[];
    double? tempo;
    for (
      var i = e;
      i < entries.length && entries[i].tstamp <= info.endMs;
      i++
    ) {
      final q = entries[i].qstamp;
      if (q == null) continue;
      if (pts.isNotEmpty && entries[i].tstamp == pts.last.$1) continue;
      pts.add((entries[i].tstamp, q));
      tempo ??= entries[i].tempo;
    }
    if (pts.isEmpty) continue;
    final q0 = pts.first.$2;
    final t0 = pts.first.$1;
    var msPerQ = 60000.0 / (tempo ?? 120.0);
    if (pts.length >= 2) {
      final (ta, qa) = pts[pts.length - 2];
      final (tb, qb) = pts.last;
      if (qb > qa) msPerQ = (tb - ta) / (qb - qa);
    }
    var seg = 0;
    for (var k = 0; ; k++) {
      final q = q0 + k;
      while (seg + 1 < pts.length && pts[seg + 1].$2 <= q) {
        seg++;
      }
      double ms;
      if (seg + 1 < pts.length) {
        final (ta, qa) = pts[seg];
        final (tb, qb) = pts[seg + 1];
        ms = ta + (q - qa) * (tb - ta) / (qb - qa);
      } else {
        final (ta, qa) = pts[seg];
        ms = ta + (q - qa) * msPerQ;
      }
      if (k == 0) ms = t0;
      if (ms >= info.endMs - 0.5) break;
      beats.add(Beat(ms, accent: k == 0, measure: m));
    }
  }
  return beats;
}

/// Cliques da contagem inicial para começar em [fromMs]: as batidas do
/// compasso que contém [fromMs], deslocadas para antes dele (o 1º clique é
/// o forte). `[]` se não houver batidas.
List<Beat> countInBeats(List<Beat> beats, double fromMs) {
  if (beats.isEmpty) return const [];
  // Compasso que contém [fromMs]: o da última batida em ou antes dele.
  var idx = beats.lastIndexWhere((b) => b.ms <= fromMs + 0.5);
  if (idx == -1) idx = 0;
  final measure = beats[idx].measure;
  final bar = beats.where((b) => b.measure == measure).toList();
  final spacing = bar.length >= 2
      ? bar[1].ms - bar[0].ms
      : (idx + 1 < beats.length ? beats[idx + 1].ms - beats[idx].ms : 500.0);
  final n = bar.length;
  return [
    for (var i = 0; i < n; i++)
      Beat(fromMs - (n - i) * spacing, accent: i == 0, measure: measure),
  ];
}

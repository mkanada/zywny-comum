// J01 — Caminho sem repetições e compassos lógicos (Dart puro).
//
// O caminho é a música sem repetições: para cada compasso, a primeira
// ocorrência em `ScoreTimeline.measures`, descartando as casas que não são
// a última (J00, "Caminho"). Compassos incompletos (anacruse, compasso
// partido em `implicit="yes"`) grudam no vizinho e viram um compasso lógico
// só — a unidade que a tela conta e que os trechos cortam.
//
// A duração em semínimas (`qstamp` do timemap) é a fonte para saber se um
// compasso é incompleto — a mesma conta que `lib/audio/metronome.dart` faz
// por compasso (uma batida por semínima). Sem `qstamp` (documento sintético
// sem ele), tudo conta como completo e nada gruda.
library;

import 'package:score_bridge/score_bridge.dart';

/// Uma ocorrência do caminho: o índice em `ScoreTimeline.measures` mais o
/// intervalo em ms musicais.
class PathMeasure {
  const PathMeasure({
    required this.occurrence,
    required this.startMs,
    required this.endMs,
  });

  /// Índice em `ScoreTimeline.measures` (ordem de execução).
  final int occurrence;
  final double startMs;
  final double endMs;
}

/// Um compasso lógico: um ou mais [PathMeasure] grudados (anacruse, compasso
/// partido). [number] é o que a tela mostra (1-based, contando lógicos).
class LogicalMeasure {
  const LogicalMeasure({
    required this.measures,
    required this.startMs,
    required this.endMs,
    required this.number,
  });

  final List<PathMeasure> measures;
  final double startMs;
  final double endMs;
  final int number;
}

/// O caminho: os compassos lógicos na ordem em que se lê, mais os índices
/// de compasso lógico antes dos quais há um salto na execução.
class TrailPath {
  const TrailPath({required this.logical, required this.jumps});

  final List<LogicalMeasure> logical;

  /// Índices lógicos antes dos quais há salto (ocorrências escolhidas não
  /// consecutivas em `ScoreTimeline.measures`). Vazio = contíguo.
  final List<int> jumps;

  bool get isContiguous => jumps.isEmpty;
  int get measureCount => logical.length;

  /// Compasso lógico que contém a ocorrência [occurrence], ou `null` se ela
  /// não está no caminho (repetição descartada, casa não final).
  int? logicalOf(int occurrence) {
    for (var i = 0; i < logical.length; i++) {
      for (final m in logical[i].measures) {
        if (m.occurrence == occurrence) return i;
      }
    }
    return null;
  }

  /// O número que a tela mostra (1-based, nos compassos do caminho) do
  /// compasso que contém a ocorrência [occurrence]; `null` fora do caminho.
  /// Mesma numeração da gaveta e do resumo (U07).
  int? numberOf(int occurrence) {
    final i = logicalOf(occurrence);
    return i == null ? null : logical[i].number;
  }

  /// Início (ms musicais) do compasso de número [number] do caminho.
  double? startMsOfNumber(int number) {
    for (final m in logical) {
      if (m.number == number) return m.startMs;
    }
    return null;
  }

  /// O caminho de [timeline], pelas regras do J00 (ver o topo do arquivo).
  static TrailPath fromTimeline(ScoreTimeline timeline) {
    final measures = timeline.measures;
    if (measures.isEmpty) {
      return const TrailPath(logical: [], jumps: []);
    }
    final docOrder = _documentOrder(timeline.document);
    final firstOccurrence = <String, int>{};
    for (var i = 0; i < measures.length; i++) {
      firstOccurrence.putIfAbsent(measures[i].id, () => i);
    }

    // Casas não finais: num salto para a frente (`isJump`, destino nunca
    // tocado antes), os compassos do documento entre a ocorrência anterior
    // e o destino são a casa descartada (J00).
    final seenIds = <String>{};
    final discardedDocIds = <String>{};
    final orderOfId = <String, int>{};
    docOrder.asMap().forEach((order, id) {
      orderOfId.putIfAbsent(id, () => order);
    });
    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      final firstTime = !seenIds.contains(m.id);
      if (i > 0 && m.isJump && firstTime) {
        final prev = measures[i - 1];
        final prevOrder = orderOfId[prev.id];
        final destOrder = orderOfId[m.id];
        if (prevOrder != null &&
            destOrder != null &&
            destOrder > prevOrder + 1) {
          for (final entry in orderOfId.entries) {
            if (entry.value > prevOrder && entry.value < destOrder) {
              discardedDocIds.add(entry.key);
            }
          }
        }
      }
      seenIds.add(m.id);
    }

    final sortedIds = firstOccurrence.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final chosen = <_Chosen>[];
    for (final e in sortedIds) {
      if (discardedDocIds.contains(e.key)) continue;
      final occ = e.value;
      chosen.add(
        _Chosen(
          occurrence: occ,
          startMs: measures[occ].startMs.toDouble(),
          endMs: measures[occ].endMs.toDouble(),
        ),
      );
    }
    if (chosen.isEmpty) {
      return const TrailPath(logical: [], jumps: []);
    }

    final quarters = measureQuarterLengths(timeline);
    for (final c in chosen) {
      c.quarters = quarters[c.occurrence];
    }
    final full = _fullQuarters([for (final c in chosen) c.quarters]);
    final groups = _glueIncomplete(chosen, full);

    final logical = <LogicalMeasure>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      logical.add(
        LogicalMeasure(
          measures: [
            for (final c in g)
              PathMeasure(
                occurrence: c.occurrence,
                startMs: c.startMs,
                endMs: c.endMs,
              ),
          ],
          startMs: g.first.startMs,
          endMs: g.last.endMs,
          number: i + 1,
        ),
      );
    }

    // Contiguidade: as ocorrências escolhidas têm que ser consecutivas na
    // execução. Dois ritornelos seguidos dão salto mesmo em ordem de
    // documento consecutiva (a 2ª passagem do primeiro fica no meio).
    final jumps = <int>[];
    for (var i = 1; i < groups.length; i++) {
      if (groups[i].first.occurrence != groups[i - 1].last.occurrence + 1) {
        jumps.add(i);
      }
    }
    return TrailPath(logical: logical, jumps: jumps);
  }
}

class _Chosen {
  _Chosen({
    required this.occurrence,
    required this.startMs,
    required this.endMs,
  });

  final int occurrence;
  final double startMs;
  final double endMs;
  double? quarters;
}

/// Ordem de documento dos compassos: ids de `measure` em pré-ordem.
List<String> _documentOrder(VsbDocument document) {
  final order = <String>[];
  void walk(SceneNode node) {
    if (node.className == 'measure' && node.id != null) {
      if (!order.contains(node.id!)) order.add(node.id!);
    }
    for (final child in node.children) {
      if (child is SceneNode) walk(child);
    }
  }

  for (final page in document.pages) {
    walk(page.root);
  }
  return order;
}

/// Duração em semínimas de cada ocorrência (`q` final − `q` inicial), ou
/// `null` quando o timemap não dá para saber (sem `qstamp`).
///
/// Mesma fonte que `metronomeBeats` usa: os pontos (`tstamp`, `qstamp`) do
/// compasso, incluindo a entrada que abre o seguinte (`tstamp == endMs`)
/// como âncora do fim.
List<double?> measureQuarterLengths(ScoreTimeline timeline) {
  final entries = timeline.entries;
  final measures = timeline.measures;
  final result = List<double?>.filled(measures.length, null);
  for (var m = 0; m < measures.length; m++) {
    final info = measures[m];
    double? first;
    double? last;
    double? lastTstamp;
    for (final e in entries) {
      if (e.tstamp < info.startMs - 0.5) continue;
      if (e.tstamp > info.endMs + 0.5) break;
      final q = e.qstamp;
      if (q == null) continue;
      if (lastTstamp != null && e.tstamp == lastTstamp) continue;
      first ??= q;
      last = q;
      lastTstamp = e.tstamp;
    }
    if (first != null && last != null && last > first) {
      result[m] = last - first;
    }
  }
  return result;
}

/// O compasso cheio: a duração mais comum entre as escolhidas. `null` sem
/// informação de `qstamp` (nada gruda).
double? _fullQuarters(List<double?> quarters) {
  final counts = <String, int>{};
  final values = <String, double>{};
  for (final q in quarters) {
    if (q == null) continue;
    final key = q.toStringAsFixed(6);
    counts[key] = (counts[key] ?? 0) + 1;
    values[key] = q;
  }
  if (counts.isEmpty) return null;
  var best = counts.entries.first;
  for (final e in counts.entries) {
    if (e.value > best.value) best = e;
  }
  return values[best.key];
}

bool _isIncomplete(_Chosen c, double? full) =>
    c.quarters != null && full != null && c.quarters! < full - 1e-9;

double _groupQuarters(List<_Chosen> group, double full) {
  var sum = 0.0;
  for (final c in group) {
    if (c.quarters == null) return full;
    sum += c.quarters!;
  }
  return sum;
}

/// Gruda incompletos (J00): o primeiro gruda para a frente (anacruse); os
/// demais, para trás ("metade final do partido gruda na inicial"). Um grupo
/// já cheio não recebe mais nada; um incompleto solitário no fim volta para
/// o grupo anterior em vez de contar sozinho.
List<List<_Chosen>> _glueIncomplete(List<_Chosen> chosen, double? full) {
  final groups = <List<_Chosen>>[];
  if (full == null) {
    return [
      for (final c in chosen) [c],
    ];
  }
  var i = 0;
  while (i < chosen.length) {
    if (groups.isEmpty) {
      final c = chosen[i];
      if (_isIncomplete(c, full) && i + 1 < chosen.length) {
        groups.add([c, chosen[i + 1]]);
        i += 2;
      } else {
        groups.add([c]);
        i += 1;
      }
      continue;
    }
    final c = chosen[i];
    final prev = groups.last;
    if (_isIncomplete(c, full)) {
      if (_groupQuarters(prev, full) < full - 1e-9) {
        prev.add(c);
      } else {
        groups.add([c]);
      }
      i += 1;
    } else {
      if (_groupQuarters(prev, full) < full - 1e-9) {
        prev.add(c);
      } else {
        groups.add([c]);
      }
      i += 1;
    }
  }
  if (groups.length > 1) {
    final last = groups.last;
    if (last.length == 1 &&
        _isIncomplete(last.single, full) &&
        _groupQuarters(last, full) < full - 1e-9) {
      groups.removeLast();
      groups.last.addAll(last);
    }
  }
  return groups;
}

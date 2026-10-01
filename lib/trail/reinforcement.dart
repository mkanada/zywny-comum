// J02 — Blocos de reforço (Dart puro): em volta dos compassos lógicos com
// erro depois de reprovar na fase final (J00, "Fase final").
//
// 1. Lógicos com erro vizinhos entre si viram um bloco.
// 2. Cada bloco ganha um compasso bom antes e um depois (quando existem).
// 3. Bloco com menos de 3 cresce até 3 (para a frente; no fim, para trás).
// 4. Blocos que se tocam ou se sobrepõem se fundem.
library;

/// Blocos em compassos lógicos ([first]..[last], inclusivos) para treinar no
/// degrau em que reprovou.
List<({int first, int last})> reinforcementBlocks(
  Set<int> badLogical,
  int measureCount,
) {
  if (measureCount <= 0) return const [];
  final sorted = badLogical.where((m) => m >= 0 && m < measureCount).toList()
    ..sort();
  if (sorted.isEmpty) return const [];

  final grouped = <({int first, int last})>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (final m in sorted.skip(1)) {
    if (m == prev + 1) {
      prev = m;
    } else {
      grouped.add((first: start, last: prev));
      start = m;
      prev = m;
    }
  }
  grouped.add((first: start, last: prev));

  final expanded = <({int first, int last})>[];
  for (final g in grouped) {
    var first = g.first > 0 ? g.first - 1 : g.first;
    var last = g.last < measureCount - 1 ? g.last + 1 : g.last;
    while (last - first + 1 < 3) {
      if (last + 1 < measureCount) {
        last++;
      } else if (first > 0) {
        first--;
      } else {
        break;
      }
    }
    if (last >= measureCount) last = measureCount - 1;
    expanded.add((first: first, last: last));
  }
  expanded.sort((a, b) => a.first.compareTo(b.first));

  final merged = <({int first, int last})>[];
  for (final g in expanded) {
    if (merged.isEmpty) {
      merged.add(g);
      continue;
    }
    final lastM = merged.last;
    if (g.first <= lastM.last + 1) {
      merged[merged.length - 1] = (
        first: lastM.first,
        last: g.last > lastM.last ? g.last : lastM.last,
      );
    } else {
      merged.add(g);
    }
  }
  return merged;
}

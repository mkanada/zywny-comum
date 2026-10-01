// J01 — Corte do caminho em trechos (Dart puro).
//
// Trechos vizinhos compartilham 1 compasso lógico (avanço = N − 1). Com M
// compassos, começam em 0, N−1, 2(N−1), … enquanto o início for menor que
// M − 1; o último vai até o fim e pode ficar menor que N (mínimo 2: o
// compartilhado e um novo). Se M ≤ N, há um trecho só (J00).
//
// Até o J08, um trecho não atravessa salto: caminho não contíguo devolve
// lista vazia e a trilha fica indisponível.
library;

import 'trail_path.dart';

/// Um trecho: [first]..[last] (índices de compasso lógico, inclusivos).
class TrailSegment {
  const TrailSegment({
    required this.index,
    required this.first,
    required this.last,
    required this.startMs,
    required this.endMs,
  });

  final int index;
  final int first;
  final int last;
  int get length => last - first + 1;
  final double startMs;
  final double endMs;
}

/// Corta [path] em trechos de [n] compassos lógicos. `n < 3` é erro de
/// programação (a UI nunca manda).
List<TrailSegment> cutSegments(TrailPath path, int n) {
  assert(n >= 3, 'n deve ser >= 3');
  if (n < 3) throw ArgumentError.value(n, 'n', 'deve ser >= 3');
  if (path.logical.isEmpty) return const [];
  if (!path.isContiguous) return const [];
  final m = path.logical.length;
  if (m <= n) {
    return [
      TrailSegment(
        index: 0,
        first: 0,
        last: m - 1,
        startMs: path.logical.first.startMs,
        endMs: path.logical.last.endMs,
      ),
    ];
  }
  final segments = <TrailSegment>[];
  for (var start = 0; start < m - 1; start += n - 1) {
    var end = start + n - 1;
    if (end >= m - 1) end = m - 1;
    segments.add(
      TrailSegment(
        index: segments.length,
        first: start,
        last: end,
        startMs: path.logical[start].startMs,
        endMs: path.logical[end].endMs,
      ),
    );
    if (end == m - 1) break;
  }
  return segments;
}

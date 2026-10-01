// J01 — Caminho sem repetições e corte em trechos.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_segments.dart';

/// Uma ocorrência na ordem de execução para o documento sintético.
class _Occ {
  const _Occ(this.id, this.pass, this.t, this.q);
  final String id;
  final int pass;
  final double t;
  final double q;
}

VsbDocument _fakeTrailDoc({
  required List<String> docOrder,
  required List<_Occ> occurrences,
  required double finalT,
  required double finalQ,
}) {
  ScenePage page() {
    final byId = <String, SceneNode>{};
    final elements = <IndexEntry>[];
    final children = <SceneChild>[];
    var path = 0;
    for (final id in docOrder) {
      final node = SceneNode(
        id: id,
        className: 'measure',
        hidden: false,
        bbox: const Rect.fromLTWH(0, 0, 100, 100),
        children: const [],
      );
      children.add(node);
      byId[id] = node;
      elements.add(
        IndexEntry(
          id: id,
          className: 'measure',
          nodePath: ++path,
          bbox: node.bbox!,
        ),
      );
    }
    return ScenePage(
      index: 0,
      width: 1000,
      height: 1400,
      contentHeight: 1400,
      viewBoxFactor: 1,
      viewBox: const Rect.fromLTWH(0, 0, 1000, 1400),
      baseWidth: 1000,
      baseHeight: 1400,
      userScaleX: 1,
      userScaleY: 1,
      widthPx: 1000,
      heightPx: 1400,
      fit: const PageFit(scale: 1, tx: 0, ty: 0),
      origin: Offset.zero,
      root: SceneNode(className: 'page', hidden: false, children: children),
      elements: elements,
      byId: byId,
    );
  }

  final timemap = <TimemapEntry>[
    for (final o in occurrences)
      TimemapEntry(
        qstamp: o.q,
        tstamp: o.t,
        on: const [],
        off: const [],
        restsOn: const [],
        restsOff: const [],
        measureOn: o.pass == 1 ? o.id : '${o.id}-rend${o.pass}',
      ),
    TimemapEntry(
      qstamp: finalQ,
      tstamp: finalT,
      on: const [],
      off: const [],
      restsOn: const [],
      restsOff: const [],
    ),
  ];
  return VsbDocument(
    manifest: const VsbManifest(
      format: 'vsb',
      version: 1,
      generator: 'test',
      pageCount: 1,
      files: VsbManifestFiles(scene: 'scene.json', glyphs: 'glyphs.json'),
    ),
    glyphs: const {},
    pages: [page()],
    timemap: timemap,
  );
}

TrailPath _path({
  required List<String> docOrder,
  required List<_Occ> occurrences,
  required double finalT,
  required double finalQ,
}) {
  final doc = _fakeTrailDoc(
    docOrder: docOrder,
    occurrences: occurrences,
    finalT: finalT,
    finalQ: finalQ,
  );
  return TrailPath.fromTimeline(ScoreTimeline(doc));
}

void main() {
  group('caminho (J01, critérios 1-4)', () {
    test('X |: A B :| x3 -> X A B, contíguo', () {
      final path = _path(
        docOrder: ['X', 'A', 'B'],
        occurrences: const [
          _Occ('X', 1, 0, 0),
          _Occ('A', 1, 1000, 4),
          _Occ('B', 1, 2000, 8),
          _Occ('A', 2, 3000, 12),
          _Occ('B', 2, 4000, 16),
          _Occ('A', 3, 5000, 20),
          _Occ('B', 3, 6000, 24),
        ],
        finalT: 7000,
        finalQ: 28,
      );
      expect(path.measureCount, 3);
      expect(path.isContiguous, isTrue);
      expect(path.jumps, isEmpty);
      expect(
        [for (final m in path.logical) m.measures.single.occurrence],
        [0, 1, 2],
      );
      expect(path.logical.first.startMs, 0);
      // B1 termina onde a 2ª passagem começa (ocorrência 3).
      expect(path.logical.last.endMs, 3000);
    });

    test('|: A B [1 C] :| [2 D] E -> A B D E, salto antes de D, C fora', () {
      final path = _path(
        docOrder: ['A', 'B', 'C', 'D', 'E'],
        occurrences: const [
          _Occ('A', 1, 0, 0),
          _Occ('B', 1, 1000, 4),
          _Occ('C', 1, 2000, 8),
          _Occ('A', 2, 3000, 12),
          _Occ('B', 2, 4000, 16),
          _Occ('D', 1, 5000, 20),
          _Occ('E', 1, 6000, 24),
        ],
        finalT: 7000,
        finalQ: 28,
      );
      expect(path.measureCount, 4);
      expect(path.isContiguous, isFalse);
      expect(path.jumps, [2]);
      // C (ocorrência 2) não está no caminho.
      expect(path.logicalOf(2), isNull);
      expect(path.logicalOf(0), 0);
      expect(path.logicalOf(1), 1);
      expect(path.logicalOf(5), 2);
      expect(path.logicalOf(6), 3);
      // J08: o corte atravessa o salto (o agendador pula o vão).
      expect(cutSegments(path, 3), hasLength(2));
    });

    test('|: A :| |: B :| -> A B com salto antes de B', () {
      final path = _path(
        docOrder: ['A', 'B'],
        occurrences: const [
          _Occ('A', 1, 0, 0),
          _Occ('A', 2, 1000, 4),
          _Occ('B', 1, 2000, 8),
          _Occ('B', 2, 3000, 12),
        ],
        finalT: 4000,
        finalQ: 16,
      );
      expect(path.measureCount, 2);
      expect(path.isContiguous, isFalse);
      expect(path.jumps, [1]);
    });

    test('anacruse gruda no seguinte; number 1 cobre os dois', () {
      final path = _path(
        docOrder: ['P', 'A', 'B'],
        occurrences: const [
          _Occ('P', 1, 0, 0),
          _Occ('A', 1, 500, 0.5),
          _Occ('B', 1, 2500, 2.5),
        ],
        finalT: 4500,
        finalQ: 4.5,
      );
      expect(path.measureCount, 2);
      expect(path.isContiguous, isTrue);
      expect(path.logical.first.number, 1);
      expect(path.logical.first.measures, hasLength(2));
      expect(
        [for (final m in path.logical.first.measures) m.occurrence],
        [0, 1],
      );
      expect(path.logical[1].number, 2);
    });
  });

  group('corte (J01, critério 5)', () {
    List<int> cut(int m, int n) {
      final doc = _fakeTrailDoc(
        docOrder: [for (var i = 0; i < m; i++) 'm$i'],
        occurrences: [
          for (var i = 0; i < m; i++) _Occ('m$i', 1, i * 1000.0, i * 4.0),
        ],
        finalT: m * 1000.0,
        finalQ: m * 4.0,
      );
      final path = TrailPath.fromTimeline(ScoreTimeline(doc));
      expect(path.isContiguous, isTrue);
      return [
        for (final s in cutSegments(path, n)) ...[s.first, s.last],
      ];
    }

    test('tabela do J00', () {
      expect(cut(8, 3), [0, 2, 2, 4, 4, 6, 6, 7]);
      expect(cut(7, 3), [0, 2, 2, 4, 4, 6]);
      expect(cut(16, 5), [0, 4, 4, 8, 8, 12, 12, 15]);
      expect(cut(4, 5), [0, 3]);
      expect(cut(20, 20), [0, 19]);
      expect(cut(21, 20), [0, 19, 19, 20]);
    });

    test('n < 3 é erro de programação', () {
      final doc = _fakeTrailDoc(
        docOrder: const ['a', 'b', 'c'],
        occurrences: const [
          _Occ('a', 1, 0, 0),
          _Occ('b', 1, 1000, 4),
          _Occ('c', 1, 2000, 8),
        ],
        finalT: 3000,
        finalQ: 12,
      );
      final path = TrailPath.fromTimeline(ScoreTimeline(doc));
      expect(
        () => cutSegments(path, 2),
        throwsA(anyOf([isA<ArgumentError>(), isA<AssertionError>()])),
      );
    });
  });

  group('fixtures (J01, critério 6)', () {
    test('erik-satie e maple-leaf-rag: caminho sem exceção', () {
      for (final name in ['erik-satie.vsb', 'maple-leaf-rag.vsb']) {
        final bytes = File('test/fixtures/$name').readAsBytesSync();
        final doc = VsbDocument.fromBytes(bytes);
        final path = TrailPath.fromTimeline(ScoreTimeline(doc));
        expect(path.measureCount, greaterThan(0), reason: name);
        // Registrado nas notas do J01: vai para o arquivo do passo.
        // ignore: avoid_print
        print(
          '$name: lógicos=${path.measureCount} '
          'contíguo=${path.isContiguous} saltos=${path.jumps.length} '
          '${path.jumps}',
        );
      }
    });
  });
}

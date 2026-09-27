// Rota de exibição na `ScoreTimeline` (P04a, regra "Player (Dart)" de P00):
// para cada ocorrência de compasso, `MeasureInfo.view` é a página que o
// player exibe — normal ou de uma sequência alternativa.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _repeticoesDir = 'test/fixtures/repeticoes';

List<File> _repeticoesFixtures() =>
    Directory(_repeticoesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.vsb'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  final mapleLeafRag = VsbDocument.fromBytes(
    File('test/fixtures/maple-leaf-rag.vsb').readAsBytesSync(),
  );

  test('critério 1: tabela de saltos da Maple Leaf Rag (8 saltos)', () {
    final tl = ScoreTimeline(mapleLeafRag);
    final jumps = [
      for (var i = 1; i < tl.measures.length; i++)
        if (tl.measures[i].isJump) i,
    ];
    // ignore: avoid_print
    print(
      'P04a — saltos da Maple Leaf Rag (origem -> destino, antes -> '
      'depois):',
    );
    for (final i in jumps) {
      final before = tl.measures[i - 1].view;
      final after = tl.measures[i].view;
      // ignore: avoid_print
      print(
        '  ${tl.measures[i].startMs}ms: ${tl.measures[i - 1].id} -> '
        '${tl.measures[i].id}  $before -> $after',
      );
      if (before == after) {
        // Passo "a" da regra: o destino já estava na página exibida — não
        // muda de view (a maioria dos saltos da Maple Leaf Rag, todos na
        // mesma página normal).
        continue;
      }
      // Único salto que cruza página nesta peça (P01c): o destino não é o
      // 1º compasso de nenhuma página normal, então cai no passo "d" — a
      // página 0 da sequência alternativa que começa nele (passo "b"/"c"
      // não achariam nada, dado que a view antes é sempre normal aqui).
      final destId = tl.measures[i].id;
      final altIndex = mapleLeafRag.alternates.indexWhere(
        (s) => s.start == destId,
      );
      expect(
        altIndex,
        isNot(-1),
        reason: 'destino $destId devia ter sequência alternativa (P02b)',
      );
      expect(after, PageRef(0, sequence: altIndex));
      expect(mapleLeafRag.alternates[altIndex].pages[0].firstMeasureId, destId);
    }
    expect(jumps.length, 8);
  });

  test('critério 2: toda ocorrência existe na página view (23 fixtures de '
      'repeticoes/)', () {
    final fixtures = _repeticoesFixtures();
    expect(fixtures.length, 23);
    for (final file in fixtures) {
      final doc = VsbDocument.fromBytes(file.readAsBytesSync());
      final tl = ScoreTimeline(doc);
      for (final m in tl.measures) {
        final page = doc.geometryOf(m.view.sequence).pageOf(m.id);
        expect(
          page,
          m.view.index,
          reason: '${file.uri.pathSegments.last} ${m.id} ${m.view}',
        );
      }
    }
  });

  test('critério 3: view só muda em fronteira de página da mesma sequência ou '
      'em salto', () {
    for (final file in _repeticoesFixtures()) {
      final doc = VsbDocument.fromBytes(file.readAsBytesSync());
      final tl = ScoreTimeline(doc);
      for (var i = 1; i < tl.measures.length; i++) {
        final m = tl.measures[i];
        final prev = tl.measures[i - 1];
        if (m.view == prev.view) {
          continue;
        }
        final sameSequenceTurn = m.view.sequence == prev.view.sequence;
        expect(
          m.isJump || sameSequenceTurn,
          isTrue,
          reason:
              '${file.uri.pathSegments.last} ${prev.id}(${prev.view}) -> '
              '${m.id}(${m.view}) isJump=${m.isJump}',
        );
      }
    }
  });

  test('useAlternates: false mantém toda view normal, mesmo com '
      'alternates.json', () {
    final tl = ScoreTimeline(mapleLeafRag, useAlternates: false);
    for (final m in tl.measures) {
      expect(m.view.isAlternate, isFalse);
      expect(m.view, PageRef(m.page));
    }
  });
}

// J02 — Avaliação da etapa e blocos de reforço.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/practice/practice_report.dart';
import 'package:zywny/practice/practice_session.dart';
import 'package:zywny/trail/reinforcement.dart';
import 'package:zywny/trail/stage_result.dart';

ReportEntry _e(PracticeVerdictKind k, int measure) => ReportEntry(
  NoteVerdict(pitch: 60, kind: k, deltaMs: 0, eventId: 'x'),
  measure,
);

void main() {
  group('StageResult.fromReport (critérios 1-4)', () {
    test('tempo real: 18+1+1 -> 90% aprovado; 17+3 -> 85% reprovado', () {
      final ok = PracticeReport([
        for (var i = 0; i < 18; i++) _e(PracticeVerdictKind.correct, 0),
        _e(PracticeVerdictKind.late, 1),
        _e(PracticeVerdictKind.missed, 2),
      ]);
      final r = StageResult.fromReport(ok);
      expect(r.hits, 18);
      expect(r.total, 20);
      expect(r.percent, 90);
      expect(r.passed, isTrue);

      final bad = PracticeReport([
        for (var i = 0; i < 17; i++) _e(PracticeVerdictKind.correct, 0),
        _e(PracticeVerdictKind.late, 1),
        _e(PracticeVerdictKind.late, 1),
        _e(PracticeVerdictKind.missed, 2),
      ]);
      final r2 = StageResult.fromReport(bad);
      expect(r2.percent, 85);
      expect(r2.passed, isFalse);
    });

    test('899/1000 -> 89, reprovado; total 0 -> reprovado', () {
      const r = StageResult(hits: 899, total: 1000, badMeasures: {});
      expect(r.percent, 89);
      expect(r.passed, isFalse);

      const empty = StageResult(hits: 0, total: 0, badMeasures: {});
      expect(empty.percent, 0);
      expect(empty.passed, isFalse);
    });
  });

  group('WaitTally (critério 5)', () {
    test('10 passos, wrong em um (2x) -> 9/10 aprovado', () {
      final tally = WaitTally();
      for (var i = 0; i < 10; i++) {
        tally.stepStarted(i, i);
        if (i == 3) {
          tally.wrong();
          tally.wrong();
        }
        tally.stepDone();
      }
      final r = tally.result();
      expect(r.hits, 9);
      expect(r.total, 10);
      expect(r.percent, 90);
      expect(r.passed, isTrue);
      expect(r.badMeasures, {3});
    });

    test('wrong em dois passos -> 8/10 reprovado; fora de passo ignora', () {
      final tally = WaitTally();
      tally.wrong();
      for (var i = 0; i < 10; i++) {
        tally.stepStarted(i, i);
        if (i == 3 || i == 7) tally.wrong();
        tally.stepDone();
      }
      tally.wrong();
      final r = tally.result();
      expect(r.hits, 8);
      expect(r.total, 10);
      expect(r.passed, isFalse);
      expect(r.badMeasures, {3, 7});
    });
  });

  group('reinforcementBlocks (critério 6)', () {
    List<List<int>> blocks(Set<int> bad, int n) => [
      for (final b in reinforcementBlocks(bad, n)) [b.first, b.last],
    ];

    test('tabela do J00 com 20 compassos', () {
      expect(blocks({7}, 20), [
        [6, 8],
      ]);
      expect(blocks({7, 8}, 20), [
        [6, 9],
      ]);
      expect(blocks({0}, 20), [
        [0, 2],
      ]);
      expect(blocks({19}, 20), [
        [17, 19],
      ]);
      expect(blocks({5, 7}, 20), [
        [4, 8],
      ]);
      expect(blocks({3, 12}, 20), [
        [2, 4],
        [11, 13],
      ]);
      expect(blocks(const {}, 20), isEmpty);
    });
  });
}

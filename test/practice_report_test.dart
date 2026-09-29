// T03: `PracticeReport` com vereditos sintéticos.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/practice/practice_report.dart';
import 'package:zywny/practice/practice_session.dart';

ReportEntry _e(
  PracticeVerdictKind k,
  int measure, {
  double delta = 0,
  int pass = 1,
}) => ReportEntry(
  NoteVerdict(pitch: 60, kind: k, deltaMs: delta, eventId: 'x'),
  measure,
  pass: pass,
);

void main() {
  group('PracticeReport', () {
    test(
      'contagens, precisão e média de adiantado/atrasado (ms de parede)',
      () {
        final r = PracticeReport([
          _e(PracticeVerdictKind.correct, 0, delta: 10),
          _e(PracticeVerdictKind.correct, 0, delta: -10),
          _e(PracticeVerdictKind.late, 1, delta: 100),
          _e(PracticeVerdictKind.early, 1, delta: -40),
          _e(PracticeVerdictKind.wrong, 1),
          _e(PracticeVerdictKind.missed, 2),
        ]);
        expect(r.total, 6);
        expect(r.correct, 2);
        expect(r.early, 1);
        expect(r.late, 1);
        expect(r.wrong, 1);
        expect(r.missed, 1);
        expect(r.accuracy, closeTo(2 / 6, 1e-9));
        // wrong/missed não entram na média: (10 - 10 + 100 - 40) / 4.
        expect(r.meanDeltaMs, closeTo(15, 1e-9));
        expect(r.meanAbsDeltaMs, closeTo(40, 1e-9));
      },
    );

    test('deltaMs musical vira parede pela speed', () {
      final r = PracticeReport([
        _e(PracticeVerdictKind.late, 0, delta: 50),
      ], speed: 0.5);
      expect(r.meanDeltaMs, closeTo(100, 1e-9));
    });

    test('piores compassos: errada/perdida primeiro, imprecisão desempata', () {
      final r = PracticeReport([
        for (var i = 0; i < 3; i++) _e(PracticeVerdictKind.wrong, 4),
        _e(PracticeVerdictKind.missed, 2),
        _e(PracticeVerdictKind.late, 2, delta: 90),
        _e(PracticeVerdictKind.missed, 7),
        _e(PracticeVerdictKind.correct, 9),
        _e(PracticeVerdictKind.late, 5, delta: 90),
      ]);
      final worst = r.worstMeasures(max: 3);
      expect([for (final m in worst) m.index], [4, 2, 7]);
      expect(r.worstMeasures().every((m) => m.index != 9), isTrue);
      expect(r.worstMeasures(max: 1).single.errors, 3);
    });

    test(
      'compasso repetido: cada ocorrência é uma linha (pass preservado)',
      () {
        final r = PracticeReport([
          _e(PracticeVerdictKind.correct, 3),
          _e(PracticeVerdictKind.wrong, 11, pass: 2),
          _e(PracticeVerdictKind.wrong, 11, pass: 2),
        ]);
        expect([for (final m in r.measures) m.index], [3, 11]);
        final second = r.measures.last;
        expect(second.pass, 2);
        expect(second.wrong, 2);
        expect(r.worstMeasures().single.index, 11);
      },
    );

    test('vazio: precisão 0, sem piores', () {
      final r = PracticeReport(const []);
      expect(r.isEmpty, isTrue);
      expect(r.accuracy, 0);
      expect(r.worstMeasures(), isEmpty);
    });
  });
}

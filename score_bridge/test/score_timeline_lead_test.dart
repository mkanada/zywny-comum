// A entrada adiantada da haste (`leadMeasures`): quem lê à primeira vista vê a
// página nova um compasso antes.
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/fake_doc.dart';

const _maxSweep = Duration(seconds: 1);
const _bar = 50.0;

/// Quatro compassos de 2 s na página 0 (começos 100, 300, 500, 700) e um na
/// página 1; uma nota por compasso, no começo dele.
ScoreTimeline _timeline({List<double> lefts = const [100, 300, 500, 700]}) {
  final names = ['a', 'b', 'c', 'd'];
  final doc = fakeDocument(
    [
      [
        for (var i = 0; i < 4; i++)
          FakeMeasure('m${names[i]}', lefts[i], [
            FakeNote('n${names[i]}', lefts[i] + 20),
          ]),
      ],
      [
        FakeMeasure('me', 100, [FakeNote('ne', 120)]),
      ],
    ],
    [
      for (var i = 0; i < 5; i++)
        (
          i * 2000.0,
          ['n${'abcde'[i]}'],
          i == 0 ? <String>[] : ['n${'abcde'[i - 1]}'],
        ),
      (10000.0, <String>[], ['ne']),
    ],
  );
  return ScoreTimeline(doc);
}

SweepCurtain? _at(ScoreTimeline tl, double ms, int lead) =>
    tl.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar, leadMeasures: lead);

void main() {
  test('sem adiantamento, a haste só entra no último compasso', () {
    final tl = _timeline();
    expect(_at(tl, 2500, 0), isNull);
    expect(_at(tl, 4500, 0), isNull);
    expect(_at(tl, 6100, 0), isNotNull);
  });

  test('com 1, a haste entra no penúltimo e fica no começo dele', () {
    final tl = _timeline();
    expect(_at(tl, 3900, 1), isNull);
    // Antes do penúltimo (começa em 4000 ms) a página é a de sempre.
    final entering = _at(tl, 4250, 1)!;
    expect(entering.pageIndex, 0);
    expect(entering.targetPageIndex, 1);
    expect(entering.edgeX, inInclusiveRange(0, 500));
    expect(_at(tl, 5000, 1)!.edgeX, 500);
    // No último, anda do começo do penúltimo ao do último e fica.
    final moving = _at(tl, 6250, 1)!.edgeX;
    expect(moving, inExclusiveRange(500, 700));
    expect(_at(tl, 6500, 1)!.edgeX, 700);
  });

  test('a borda nunca recua até a conclusão', () {
    final tl = _timeline();
    var last = 0.0;
    for (var ms = 4000.0; ms < 8000; ms += 50) {
      final c = _at(tl, ms, 1);
      if (c == null) continue;
      expect(c.edgeX, greaterThanOrEqualTo(last), reason: '$ms ms');
      last = c.edgeX;
    }
  });

  test('o último compasso que abre um sistema novo não adianta', () {
    // O último volta ao começo da linha (um sistema novo): sem adiantamento.
    final tl = _timeline(lefts: const [100, 300, 500, 100]);
    expect(_at(tl, 4250, 1), isNull);
    expect(_at(tl, 6100, 1), isNotNull);
  });

  // Relatório de bug 55d: uma página de um compasso seguida de uma de dois. O
  // primeiro compasso da de dois começa à esquerda do 0 do viewBox (a clave e a
  // armadura vêm antes dele), e a entrada adiantada ia até lá: uma haste de
  // borda negativa, que a vista não aceita — e como o player só leva a vista à
  // página nova quando não há haste, a página velha ficava na tela um compasso
  // inteiro enquanto a nova já tocava.
  group('página de dois compassos depois de uma de um', () {
    ScoreTimeline timeline() {
      final doc = fakeDocument(
        [
          [
            FakeMeasure('ma', 100, [FakeNote('na', 120)]),
          ],
          [
            FakeMeasure('mb', -95, [FakeNote('nb', -70)]),
            FakeMeasure('mc', 400, [FakeNote('nc', 420)]),
          ],
          [
            FakeMeasure('md', 100, [FakeNote('nd', 120)]),
          ],
        ],
        [
          (0.0, ['na'], <String>[]),
          (2000.0, ['nb'], ['na']),
          (4000.0, ['nc'], ['nb']),
          (6000.0, ['nd'], ['nc']),
          (8000.0, <String>[], ['nd']),
        ],
      );
      return ScoreTimeline(doc);
    }

    test(
      'a haste nunca tem borda negativa: sem haste, vale a página de repouso',
      () {
        final tl = timeline();
        for (var ms = 0.0; ms < 8000; ms += 25) {
          final c = _at(tl, ms, 1);
          if (c == null) continue;
          expect(c.edgeX, greaterThanOrEqualTo(0), reason: '$ms ms');
        }
        // No 1º compasso da página 1 (2000 a 4000 ms), quando a haste da
        // página 0 já acabou, a página 1 é a que aparece.
        expect(_at(tl, 3500, 1), isNull);
        expect(
          tl.shownViewAt(3500, maxSweep: _maxSweep, barWidth: _bar),
          const PageRef(1),
        );
      },
    );
  });
}

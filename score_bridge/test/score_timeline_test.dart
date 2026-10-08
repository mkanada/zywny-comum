// A regra da haste (A05b): `ScoreTimeline.curtainAt` é função pura.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/fake_doc.dart';
import 'support/render_helpers.dart';
import 'support/sweep_rule.dart';

const _maxSweep = Duration(seconds: 1);
const _bar = 50.0;

/// A página à mostra em [ms] sem haste (`ScoreTimeline.shownViewAt`).
PageRef _shown(ScoreTimeline tl, double ms) =>
    tl.shownViewAt(ms, maxSweep: _maxSweep, barWidth: _bar);

void main() {
  group('índice de compassos (A05a, critério 7)', () {
    final files = corpusFiles();
    if (files.isEmpty) {
      test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
      return;
    }
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      test(name, () {
        final doc = VsbDocument.fromBytes(f.readAsBytesSync());
        final tl = ScoreTimeline(doc);
        final ms = tl.measures;
        expect(ms, isNotEmpty);
        for (var i = 0; i < ms.length; i++) {
          expect(doc.pages[ms[i].page].byId.containsKey(ms[i].id), isTrue);
          if (i + 1 < ms.length) {
            expect(ms[i + 1].startMs, greaterThan(ms[i].startMs));
            expect(ms[i].endMs, ms[i + 1].startMs);
          } else {
            expect(ms[i].endMs, tl.durationMs.round());
          }
        }
        // Todas as notas do compasso existem na página dele.
        for (final m in ms) {
          for (final n in m.noteIds) {
            expect(doc.pages[m.page].byId.containsKey(n), isTrue);
          }
        }
      });
    }
  });

  group('tempos da regra com compassos do corpus (A05b, critério 3)', () {
    final files = corpusFiles();
    if (files.isEmpty) {
      return;
    }
    test('entrada, estacionada e conclusão; D curto e D = 1 s', () {
      var checkedShort = false, checkedLong = false;
      for (final f in files) {
        final doc = VsbDocument.fromBytes(f.readAsBytesSync());
        final tl = ScoreTimeline(doc);
        final ms = tl.measures;
        for (var i = 0; i + 1 < ms.length; i++) {
          final m = ms[i];
          final next = ms[i + 1];
          if (next.page != m.page + 1) continue;
          final onPage = ms.where((x) => x.page == m.page).length;
          if (onPage < 2) continue;
          final dM = (m.endMs - m.startMs).toDouble();
          final d = math.min(1000.0, dM / 4);
          if (d <= 0) continue;
          final short = d < 1000;
          if ((short && checkedShort) || (!short && checkedLong)) continue;
          final page = doc.pages[m.page];
          final x = doc.geometry.elementOf(m.id)!.bbox.left;
          final end = sweepEndX(page, _bar);
          SweepCurtain? at(double t) =>
              tl.curtainAt(t, maxSweep: _maxSweep, barWidth: _bar);
          final s = m.startMs.toDouble();
          final l = lastEventMs(doc, m);
          final nextRight = doc.geometry.elementOf(next.id)!.bbox.right;
          final revealX = nextRight + _bar;
          final c = concStart(
            m: m,
            d: d,
            lastMs: l,
            fromX: x,
            endX: end,
            revealX: revealX,
          );
          expect(at(s - 1), isNull, reason: '$f antes da entrada');
          expect(at(s)?.edgeX ?? 0, closeTo(0, 1e-9));
          final mid = at(s + d / 2)!;
          expect(mid.pageIndex, m.page);
          expect(mid.edgeX, closeTo(x / 2, 1e-6));
          expect(at(s + d)!.edgeX, closeTo(x, 1e-6));
          expect(at((s + d + c) / 2)!.edgeX, closeTo(x, 1e-6));
          // A conclusão começa em `c`, antes de o compasso seguinte começar.
          expect(c, lessThan(next.startMs), reason: '$f virada tardia');
          expect(at(c)!.edgeX, closeTo(x, 1e-6));
          expect(at(c + d / 2)!.edgeX, closeTo(x + (end - x) / 2, 1e-6));
          expect(at(c + d), isNull, reason: 'repouso da página seguinte');
          expect(_shown(tl, c + d), next.view);
          expect(_shown(tl, c + d - 1), m.view, reason: 'ainda varrendo');
          expect(tl.restPageAt(s - 1), m.page);
          // Na última nota ou pausa de M o 1º compasso da página nova já
          // está inteiro à vista e nítido — salvo quando a entrada da haste
          // não deixa tempo (c == s + d).
          if (c > s + d) {
            final atLast = at(l)!;
            expect(
              atLast.blur,
              closeTo(0, 1e-9),
              reason: '$f nítida na última nota',
            );
            expect(atLast.edgeX, greaterThanOrEqualTo(revealX - 1e-6));
          }
          if (short) {
            checkedShort = true;
          } else {
            checkedLong = true;
            expect(d, 1000);
          }
          // ignore: avoid_print
          print(
            '${f.uri.pathSegments.last}: M=${m.id} dM=$dM D=$d '
            'xInício=$x',
          );
        }
      }
      expect(checkedShort, isTrue, reason: 'algum compasso curto');
      // O corpus não tem compasso ≥ 4 s antes de uma virada; o caso D = 1 s
      // é coberto no documento sintético (`checkedLong` é só informativo).
      // ignore: avoid_print
      print('D = 1 s no corpus: $checkedLong');
    });
  });

  group('documento sintético', () {
    // Página 0: dois compassos; página 1: um compasso com 3 notas;
    // página 2: um compasso com 1 nota; página 3: um compasso.
    late VsbDocument doc;
    late ScoreTimeline tl;
    setUp(() {
      doc = fakeDocument(
        [
          [
            FakeMeasure('m1', 100, [FakeNote('a1', 120)]),
            FakeMeasure('m2', 500, [FakeNote('a2', 520)]),
          ],
          [
            FakeMeasure('m3', 100, [
              FakeNote('b1', 150),
              FakeNote('b2', 300),
              FakeNote('b3', 450),
            ]),
          ],
          [
            FakeMeasure('m4', 100, [FakeNote('c1', 200)]),
          ],
          [
            FakeMeasure('m5', 100, [FakeNote('d1', 200)]),
          ],
        ],
        [
          (0, ['a1'], []),
          (4000, ['a2'], ['a1']),
          (8000, ['b1'], ['a2']),
          (10000, ['b2'], ['b1']),
          (12000, ['b3'], ['b2']),
          (16000, ['c1'], ['b3']),
          (20000, ['d1'], ['c1']),
          (24000, [], ['d1']),
        ],
      );
      tl = ScoreTimeline(doc);
    });

    SweepCurtain? at(double t) =>
        tl.curtainAt(t, maxSweep: _maxSweep, barWidth: _bar);

    test('compassos e páginas', () {
      expect(tl.measures.map((m) => m.id), ['m1', 'm2', 'm3', 'm4', 'm5']);
      expect(tl.measures.map((m) => m.page), [0, 0, 1, 2, 3]);
      expect(tl.measures[2].noteIds, ['b1', 'b2', 'b3']);
      expect(tl.measures.last.endMs, 24000);
    });

    test('página com dois compassos: regra geral (D = 1 s)', () {
      // M = m2 (4000..8000, D = min(1000, 1000) = 1000), xInício = 500, uma
      // nota só em 4000 (L = 4000). A conclusão não pode começar antes de a
      // entrada acabar (5000): termina em 6000, bem antes de m3 começar.
      expect(at(3999), isNull);
      expect(at(4500)!.edgeX, closeTo(250, 1e-9));
      expect(at(5000)!.edgeX, closeTo(500, 1e-9));
      final end = sweepEndX(doc.pages[0], _bar);
      expect(at(5500)!.edgeX, closeTo(500 + (end - 500) / 2, 1e-9));
      expect(at(6000), isNull);
      expect(at(7999), isNull);
      expect(_shown(tl, 6000), const PageRef(1));
      expect(_shown(tl, 5999), const PageRef(0));
    });

    test('a página nova está nítida antes da última nota ou pausa', () {
      // Página 0: m1 (0..4000) e m2 (4000..8000), que começa à esquerda
      // (x = 100) e tem notas em 4000 e 7000. A página 1 abre com m3
      // (100..500): a borda precisa passar de 500 + largura da haste (550)
      // e o desfoque cair a zero já em L = 7000. D = 1000 e
      // out* = (550 − 100) / (1050 − 100) ≈ 0,474, então C ≈ 6526.
      final d = fakeDocument(
        [
          [
            FakeMeasure('m1', 500, [FakeNote('a1', 520)]),
            FakeMeasure('m2', 100, [FakeNote('a2', 120), FakeNote('a3', 300)]),
          ],
          [
            FakeMeasure('m3', 100, [FakeNote('b1', 120)]),
          ],
        ],
        [
          (0, ['a1'], []),
          (4000, ['a2'], ['a1']),
          (7000, ['a3'], ['a2']),
          (8000, ['b1'], ['a3']),
          (12000, [], ['b1']),
        ],
      );
      final t = ScoreTimeline(d);
      SweepCurtain? c(double ms) =>
          t.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar);
      final end = sweepEndX(d.pages[0], _bar);
      final out = (550 - 100) / (end - 100);
      final conc = 7000 - out * 1000;
      expect(c(conc - 1)!.edgeX, closeTo(100, 1e-9));
      expect(c(conc - 1)!.blur, 1);
      expect(c(conc)!.edgeX, closeTo(100, 1e-9));
      final atLast = c(7000)!;
      expect(atLast.edgeX, closeTo(550, 1e-9));
      expect(atLast.blur, closeTo(0, 1e-9));
      expect(c(conc + 1000 - 1)!.edgeX, closeTo(end, 1.1));
      expect(c(conc + 1000), isNull);
      expect(_shown(t, conc + 1000), const PageRef(1));
    });

    test('uma pausa também conta como a última nota do compasso', () {
      // O mesmo, com a nota de 7000 trocada por uma pausa: L continua 7000.
      final d = fakeDocument(
        [
          [
            FakeMeasure('m1', 500, [FakeNote('a1', 520)]),
            FakeMeasure('m2', 100, [FakeNote('a2', 120)]),
          ],
          [
            FakeMeasure('m3', 100, [FakeNote('b1', 120)]),
          ],
        ],
        [
          (0, ['a1'], []),
          (4000, ['a2'], ['a1']),
          (8000, ['b1'], ['a2']),
          (12000, [], ['b1']),
        ],
        rests: [
          (7000, ['r1']),
        ],
      );
      final t = ScoreTimeline(d);
      SweepCurtain? c(double ms) =>
          t.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar);
      final atRest = c(7000)!;
      expect(atRest.edgeX, closeTo(550, 1e-9));
      expect(atRest.blur, closeTo(0, 1e-9));
      expect(c(7526), isNotNull);
      expect(c(7527), isNull);
    });

    test('compasso único com poucas notas: a haste fica no começo', () {
      // Página 1: m3 (x = 100) = 8000..16000 com b1, b2, b3; D = 1000. A
      // página aparece em 8000 + D(m2) = 9000 (fim da conclusão anterior).
      // Com 3 notas só, nenhuma é a 4ª pendente: a haste, 3 notas atrás da
      // pendente, não sai do começo do compasso (x = 100).
      expect(at(9000)?.edgeX ?? 0, closeTo(0, 1e-9));
      final entry = at(9500)!;
      expect(entry.pageIndex, 1);
      expect(entry.edgeX, closeTo(50, 1e-9));
      for (final t in <double>[10000, 10500, 11000, 11999, 12000]) {
        expect(at(t)!.edgeX, closeTo(100, 1e-9), reason: 't=$t');
        expect(at(t)!.blur, 1);
      }
      // A conclusão começa na última nota (b3, 12000), não antes: a haste
      // varreria notas por tocar.
      final end = sweepEndX(doc.pages[1], _bar);
      expect(at(12000)!.edgeX, closeTo(100, 1e-9));
      expect(at(12500)!.edgeX, closeTo(100 + (end - 100) / 2, 1e-9));
      expect(at(13000), isNull);
      expect(_shown(tl, 12999), const PageRef(1));
      expect(_shown(tl, 13000), const PageRef(2));
      // 17000 já está na entrada da página seguinte (aparece em 17000).
      expect(at(17000)?.pageIndex, 2);
      expect(at(17000)?.edgeX ?? 0, closeTo(0, 1e-9));
    });

    test('compasso único: a haste fica 3 notas atrás da nota pendente', () {
      // m1 (x = 100) = 0..12000, com 6 notas de 2 s (x = 150, 250, ... 650).
      // D = 1000. A haste vai para a nota (pendente − 3) em 1 s, a partir do
      // ataque da anterior.
      final xs = [150.0, 250.0, 350.0, 450.0, 550.0, 650.0];
      final d = fakeDocument(
        [
          [
            FakeMeasure('m1', 100, [
              for (var i = 0; i < 6; i++) FakeNote('n$i', xs[i]),
            ]),
          ],
          [
            FakeMeasure('m2', 100, [FakeNote('b1', 120)]),
          ],
        ],
        [
          for (var i = 0; i < 6; i++)
            (i * 2000.0, ['n$i'], [if (i > 0) 'n${i - 1}']),
          (12000, ['b1'], ['n5']),
          (16000, [], ['b1']),
        ],
      );
      final t = ScoreTimeline(d);
      SweepCurtain? c(double ms) =>
          t.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar);
      final end = sweepEndX(d.pages[0], _bar);

      // Entrada rumo ao começo do compasso, depois parada nele.
      expect(c(500)!.edgeX, closeTo(50, 1e-9));
      expect(c(1000)!.edgeX, closeTo(100, 1e-9));
      expect(c(3999)!.edgeX, closeTo(100, 1e-9));
      // Pendente = nota 3 (ataque da nota 2, 4000): vai para a nota 0.
      expect(c(4500)!.edgeX, closeTo(125, 1e-9));
      expect(c(5000)!.edgeX, closeTo(150, 1e-9));
      expect(c(5999)!.edgeX, closeTo(150, 1e-9));
      // Pendente = nota 4 (6000): nota 1. Pendente = nota 5 (8000): nota 2.
      expect(c(6500)!.edgeX, closeTo(200, 1e-9));
      expect(c(7000)!.edgeX, closeTo(250, 1e-9));
      expect(c(9000)!.edgeX, closeTo(350, 1e-9));
      // Última nota em 10000: a conclusão começa ali, de onde a haste está.
      expect(c(9999)!.edgeX, closeTo(350, 1e-9));
      expect(c(10000)!.edgeX, closeTo(350, 1e-9));
      expect(c(10500)!.edgeX, closeTo(350 + (end - 350) / 2, 1e-9));
      expect(c(11000), isNull);

      // Em todo instante há ao menos 3 notas entre a haste e a pendente.
      for (var ms = 0.0; ms < 10000; ms += 10) {
        final edge = c(ms)?.edgeX;
        if (edge == null) continue;
        var pending = xs.length;
        for (var i = 0; i < xs.length; i++) {
          if (i * 2000.0 > ms) {
            pending = i;
            break;
          }
        }
        final between = [
          for (var i = 0; i < pending; i++)
            if (xs[i] >= edge - 1e-9) i,
        ];
        expect(
          between.length,
          greaterThanOrEqualTo(pending < 3 ? pending : 3),
          reason: 'ms=$ms edge=$edge pendente=$pending',
        );
      }
    });

    test(
      'uma nota só: a conclusão começa quando a haste termina de entrar',
      () {
        // Página 2: c1 em 16000, compasso 16000..20000; D = 1000. A página só
        // aparece em 17000 (fim da conclusão da página 1), então a haste entra
        // em 17000..18000 e a conclusão começa em 18000 — a nota já acendeu.
        expect(at(17500)!.pageIndex, 2);
        expect(at(17500)!.edgeX, closeTo(50, 1e-9));
        final end = sweepEndX(doc.pages[2], _bar);
        // A haste espera no começo do compasso (x = 100), não na nota.
        expect(at(18000)!.edgeX, closeTo(100, 1e-9));
        expect(at(18500)!.edgeX, closeTo(100 + (end - 100) / 2, 1e-9));
        expect(at(19000), isNull);
      },
    );

    test('uma nota só, página que aparece cedo: a conclusão logo após a '
        'entrada', () {
      final d = fakeDocument(
        [
          [
            FakeMeasure('m1', 100, [FakeNote('a1', 120)]),
          ],
          [
            FakeMeasure('m2', 100, [FakeNote('b1', 300)]),
          ],
          [
            FakeMeasure('m3', 100, [FakeNote('c1', 300)]),
          ],
        ],
        [
          (0, ['a1'], []),
          (400, ['b1'], ['a1']),
          (1400, ['c1'], ['b1']),
          (2000, [], ['c1']),
        ],
      );
      final t = ScoreTimeline(d);
      SweepCurtain? c(double ms) =>
          t.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar);
      final end = sweepEndX(d.pages[1], _bar);
      // m1 (0..400, D = 100). Página 1 aparece em 400 + 100 = 500; m2 mede
      // 1000 (D = 250) e a haste entra em 500..750. b1 acende em 400, antes
      // de a página aparecer: a conclusão começa ao fim da entrada, 750.
      expect(c(600)!.edgeX, closeTo(40, 1e-9));
      expect(c(749)!.edgeX, closeTo(100 * 249 / 250, 1e-9));
      expect(c(750)!.edgeX, closeTo(100, 1e-9));
      expect(c(875)!.edgeX, closeTo(100 + (end - 100) / 2, 1e-9));
      expect(c(1000), isNull);
    });

    test('última página: nunca há haste', () {
      for (final t in <double>[20000, 21000, 23999, 24000]) {
        expect(at(t), isNull);
      }
      expect(tl.restPageAt(21000), 3);
    });

    test('função pura: mesma posição, mesma haste (seek == reprodução)', () {
      final rng = math.Random(3);
      for (var i = 0; i < 50; i++) {
        final t = rng.nextDouble() * 24000;
        expect(at(t), at(t));
      }
    });
  });
}

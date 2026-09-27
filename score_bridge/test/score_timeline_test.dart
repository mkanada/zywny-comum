// A regra da haste (A05b): `ScoreTimeline.curtainAt` é função pura.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/fake_doc.dart';
import 'support/render_helpers.dart';

const _maxSweep = Duration(seconds: 1);
const _bar = 50.0;

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
          final e = next.startMs.toDouble();
          expect(at(s - 1), isNull, reason: '$f antes da entrada');
          expect(at(s)?.edgeX ?? 0, closeTo(0, 1e-9));
          final mid = at(s + d / 2)!;
          expect(mid.pageIndex, m.page);
          expect(mid.edgeX, closeTo(x / 2, 1e-6));
          expect(at(s + d)!.edgeX, closeTo(x, 1e-6));
          expect(at((s + d + e) / 2)!.edgeX, closeTo(x, 1e-6));
          expect(at(e - 0.001)!.edgeX, closeTo(x, 1e-6));
          expect(at(e)!.edgeX, closeTo(x, 1e-6));
          expect(at(e + d / 2)!.edgeX, closeTo(x + (end - x) / 2, 1e-6));
          expect(at(e + d), isNull, reason: 'repouso da página seguinte');
          expect(tl.restPageAt(e + d), next.page);
          expect(tl.restPageAt(s - 1), m.page);
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
      // M = m2 (4000..8000, D = min(1000, 1000) = 1000), xInício = 500.
      expect(at(3999), isNull);
      expect(at(4500)!.edgeX, closeTo(250, 1e-9));
      expect(at(5000)!.edgeX, closeTo(500, 1e-9));
      expect(at(7999)!.edgeX, closeTo(500, 1e-9));
      final end = sweepEndX(doc.pages[0], _bar);
      expect(at(8500)!.edgeX, closeTo(500 + (end - 500) / 2, 1e-9));
    });

    test('compasso único com várias notas: a haste acompanha as notas', () {
      // Página 1: m3 = 8000..16000; D = 1000. A página aparece em
      // 8000 + D(m2) = 9000 (fim da conclusão anterior).
      expect(at(9000)?.edgeX ?? 0, closeTo(0, 1e-9));
      // Entrada em 9000..10000 rumo a antes de b1 (x=150) — mas a nota b2
      // (10000) já começou a puxar a haste: posição-alvo em 9000..10000 é
      // b1→b2 saltando desde 8000 (dur 1000): já em b2 em 9000.
      final entry = at(9500)!;
      expect(entry.pageIndex, 1);
      expect(entry.edgeX, greaterThan(0));
      // Estacionada antes de b2 (x=300) entre saltos.
      expect(
        at(11000)!.edgeX,
        closeTo(450, 1e-9),
        reason: 'já saltou para b3 (salto começa em 10000, dura 1000)',
      );
      expect(at(10500)!.edgeX, closeTo(300 + 150 / 2, 1e-9));
      // Conclusão só começa na primeira nota do compasso seguinte (16000).
      expect(at(15999)!.edgeX, closeTo(450, 1e-9));
      final end = sweepEndX(doc.pages[1], _bar);
      expect(at(16500)!.edgeX, closeTo(450 + (end - 450) / 2, 1e-9));
      // 17000 já está na entrada da página seguinte (aparece em 17000).
      expect(at(17000)?.pageIndex, 2);
      expect(at(17000)?.edgeX ?? 0, closeTo(0, 1e-9));
    });

    test('uma nota só: a conclusão começa 0,5 s após o destaque', () {
      // Página 2: c1 em 16000, compasso 16000..20000; D = 1000. A página só
      // aparece em 17000 (fim da conclusão da página 1), então a haste entra
      // em 17000..18000 e a conclusão começa em max(16500, 18000).
      expect(at(17500)!.pageIndex, 2);
      expect(at(17500)!.edgeX, closeTo(100, 1e-9));
      final end = sweepEndX(doc.pages[2], _bar);
      expect(at(18000)!.edgeX, closeTo(200, 1e-9));
      expect(at(18500)!.edgeX, closeTo(200 + (end - 200) / 2, 1e-9));
      expect(at(19000), isNull);
    });

    test('uma nota só, página que aparece cedo: 0,5 s exatos', () {
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
      // 1000 (D = 250). b1 acende em 400: a conclusão começa em
      // max(400 + 500, 500 + 250) = 900.
      expect(c(600)!.edgeX, closeTo(120, 1e-9));
      expect(c(899)!.edgeX, closeTo(300, 1e-9));
      expect(c(900)!.edgeX, closeTo(300, 1e-9));
      expect(c(1025)!.edgeX, closeTo(300 + (end - 300) / 2, 1e-9));
      expect(c(1150), isNull);
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

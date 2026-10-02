// Virada de página no modo espera (`ScorePlayer.waitTarget`): com o relógio
// parado no freio, a página anterior sai sozinha, em tempo de parede.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_test.dart' show Cleanup, ManualClock, testPlayer;
import 'support/fake_doc.dart';
import 'support/render_helpers.dart';

/// Duas páginas de dois compassos de 4 s; a virada 0→1 é em 8000 ms.
VsbDocument twoPages() => fakeDocument(
  [
    [
      FakeMeasure('m1', 100, [FakeNote('a1', 120)]),
      FakeMeasure('m2', 500, [FakeNote('a2', 520)]),
    ],
    [
      FakeMeasure('m3', 100, [FakeNote('b1', 120)]),
      FakeMeasure('m4', 500, [FakeNote('b2', 520)]),
    ],
  ],
  [
    (0, ['a1'], []),
    (4000, ['a2'], ['a1']),
    (8000, ['b1'], ['a2']),
    (12000, ['b2'], ['b1']),
    (16000, [], ['b2']),
  ],
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('virada no modo espera (waitTarget)', () {
    // Relógio parado (o freio do modo espera) e a vista ligada ao player.
    Future<({ScorePlayer player, ScoreViewController vc, ManualClock clock})>
    parked(WidgetTester tester, Cleanup cleanup, VsbDocument doc) async {
      final controller = ScoreController(document: doc);
      final vc = ScoreViewController();
      final clock = ManualClock();
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
        release: Duration.zero,
      )..clock = clock;
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final p0 = doc.pages[0];
      await pumpAtSize(
        tester,
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
        p0.widthPx,
        p0.heightPx,
      );
      return (player: player, vc: vc, clock: clock);
    }

    ({MeasureInfo last, MeasureInfo next}) firstTurn(ScorePlayer player) {
      final ms = player.measures;
      final i = ms.indexWhere(
        (m) => m.page == 0 && ms[ms.indexOf(m) + 1].page == 1,
      );
      return (last: ms[i], next: ms[i + 1]);
    }

    Future<void> pumpFor(WidgetTester tester, Duration total) async {
      const frame = Duration(milliseconds: 16);
      for (var t = Duration.zero; t < total; t += frame) {
        await tester.pump(frame);
      }
    }

    testPlayer('sem waitTarget, relógio parado na 1ª nota da página seguinte: '
        'a haste fica estacionada (o defeito)', (tester, cleanup) async {
      final h = await parked(tester, cleanup, twoPages());
      final turn = firstTurn(h.player);
      h.clock.positionMs = turn.next.startMs.toDouble();
      h.player.seek(Duration(milliseconds: turn.next.startMs));
      h.player.play();
      await pumpFor(tester, const Duration(seconds: 2));
      expect(h.player.curtain.value, isNotNull);
      expect(h.vc.currentPage, 0);
    });

    testPlayer('nota pendente na página seguinte, relógio ainda no último '
        'compasso: a página anterior sai em tempo de parede', (
      tester,
      cleanup,
    ) async {
      final h = await parked(tester, cleanup, twoPages());
      final turn = firstTurn(h.player);
      final at = (turn.last.startMs + turn.last.endMs) / 2;
      h.clock.positionMs = at;
      h.player.seek(Duration(milliseconds: at.round()));
      h.player.play();
      await tester.pump(const Duration(milliseconds: 16));
      final before = h.player.curtain.value;
      expect(before, isNotNull);

      // O aluno acertou a última nota da página: a pendente é a 1ª da
      // seguinte. A posição não anda mais.
      h.player.waitTarget = turn.next.startMs.toDouble();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final moving = h.player.curtain.value;
      expect(moving, isNotNull);
      expect(moving!.pageIndex, 0);
      expect(moving.edgeX, greaterThan(before!.edgeX));

      await pumpFor(tester, h.vc.maxSweepDuration * 2);
      expect(h.player.curtain.value, isNull);
      expect(h.vc.currentPage, turn.next.page);
      expect(find.byType(ClipRect), findsNothing);
      expect(h.player.position, Duration(milliseconds: at.round()));

      // A posição alcança a página nova: nada volta atrás.
      h.clock.positionMs = turn.next.startMs + 5000.0;
      await pumpFor(tester, const Duration(milliseconds: 100));
      expect(h.player.curtain.value, isNull);
      expect(h.vc.currentPage, turn.next.page);
    });

    testPlayer('relógio já parado no começo da saída da haste: conclui', (
      tester,
      cleanup,
    ) async {
      final h = await parked(tester, cleanup, twoPages());
      final turn = firstTurn(h.player);
      final at = (turn.last.startMs + turn.last.endMs) / 2;
      h.clock.positionMs = at;
      h.player.seek(Duration(milliseconds: at.round()));
      h.player.play();
      // Alvo ainda na página 0: nada muda.
      h.player.waitTarget = at;
      h.clock.positionMs = turn.next.startMs.toDouble();
      await pumpFor(tester, const Duration(milliseconds: 100));
      expect(h.player.curtain.value, isNotNull);
      expect(h.vc.currentPage, 0);

      h.player.waitTarget = turn.next.startMs.toDouble();
      await pumpFor(tester, h.vc.maxSweepDuration * 2);
      expect(h.player.curtain.value, isNull);
      expect(h.vc.currentPage, turn.next.page);
    });

    testPlayer('seek para a 1ª nota da página com alvo nela: entra direto, '
        'sem animação; waitTarget null devolve a haste da posição', (
      tester,
      cleanup,
    ) async {
      final h = await parked(tester, cleanup, twoPages());
      final turn = firstTurn(h.player);
      h.player.waitTarget = turn.next.startMs.toDouble();
      h.clock.positionMs = turn.next.startMs.toDouble();
      h.player.seek(Duration(milliseconds: turn.next.startMs));
      await tester.pump();
      expect(h.player.curtain.value, isNull);
      expect(h.vc.currentPage, turn.next.page);

      h.player.waitTarget = null;
      await tester.pump();
      expect(h.player.curtain.value, isNotNull);
      expect(h.vc.currentPage, 0);
    });
  });
}

// O rastro da partitura (`ScoreTrace`): com um sink ligado, o player e a vista
// contam a virada de página no log — o que o relatório de bug precisa para
// dizer onde uma virada se perdeu.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_test.dart' show ManualClock;
import 'support/fake_doc.dart';
import 'support/render_helpers.dart';

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
  tearDown(() => ScoreTrace.sink = null);

  testWidgets('a virada de página fica no rastro, do começo da haste ao '
      'showPage', (tester) async {
    final lines = <String>[];
    ScoreTrace.sink = (tag, message) => lines.add('[$tag] $message');
    final doc = twoPages();
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final clock = ManualClock();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: Duration.zero,
    )..clock = clock;
    addTearDown(() {
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

    player.play();
    for (var ms = 0; ms <= 9000; ms += 100) {
      clock.positionMs = ms.toDouble();
      await tester.pump(const Duration(milliseconds: 100));
    }

    player.pause();
    controller.clearAll();
    await tester.pump(const Duration(seconds: 1));
    final text = lines.join('\n');
    expect(text, contains('[player] play em'));
    expect(text, contains('[player] andamento:'));
    expect(text, contains('[player] compasso 3/4'));
    expect(text, contains('[haste] começa'));
    expect(text, contains('[haste] termina'));
    expect(vc.currentPage, 1, reason: text);
    expect(text, contains('[vista] página corrente p1 → p2'));
  });

  testWidgets('sem sink, nada é montado', (tester) async {
    var built = 0;
    ScoreTrace.log('x', () {
      built++;
      return 'y';
    });
    expect(built, 0);
  });
}

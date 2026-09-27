// `ScorePlayer` segue a rota de páginas alternativas (P04b): tocando, a
// vista mostra as alternativas nos saltos; parado (`pause`), a navegação do
// usuário continua só em páginas normais.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  final doc = VsbDocument.fromBytes(
    File('test/fixtures/maple-leaf-rag.vsb').readAsBytesSync(),
  );

  Widget view(
    VsbDocument doc, {
    required ScoreViewController vc,
    required ScoreController controller,
    ScorePageMode mode = ScorePageMode.pagedSweep,
    ValueListenable<SweepCurtain?>? curtain,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: ScoreView(
      document: doc,
      viewController: vc,
      controller: controller,
      mode: mode,
      curtain: curtain,
    ),
  );

  /// `MeasureInfo.view` em ordem de execução, sem repetir consecutivos —
  /// a sequência de páginas que um player tocando do início ao fim deve
  /// exibir (P04a).
  List<PageRef> expectedViewSequence(ScoreTimeline tl) {
    final result = <PageRef>[];
    for (final m in tl.measures) {
      if (result.isEmpty || result.last != m.view) {
        result.add(m.view);
      }
    }
    return result;
  }

  Future<void> playToEnd(WidgetTester tester, ScorePlayer player) async {
    var steps = 0;
    while (player.position < player.duration && steps < 20000) {
      player.advance(const Duration(milliseconds: 200)); // 50ms timemap * 4x
      await tester.pump();
      steps++;
    }
    expect(player.position, player.duration);
  }

  for (final mode in [ScorePageMode.pagedSweep, ScorePageMode.pagedSlide]) {
    testWidgets('critério 1 e 2: $mode, 4x do início ao fim — sequência de '
        'displayedPage bate com a rota de P04a', (tester) async {
      final vc = ScoreViewController();
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      await pumpAtSize(
        tester,
        view(doc, vc: vc, controller: controller, mode: mode),
        doc.pages[0].widthPx,
        doc.pages[0].heightPx,
      );
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
      );
      addTearDown(player.dispose);

      final tl = ScoreTimeline(doc);
      final expected = expectedViewSequence(tl);
      final observed = <PageRef>[vc.displayedPage];

      while (player.position < player.duration) {
        player.advance(const Duration(milliseconds: 200));
        await tester.pump();
        if (vc.displayedPage != observed.last) {
          observed.add(vc.displayedPage);
        }
      }
      expect(player.position, player.duration);
      expect(observed, expected);
      controller.clearAll();
    });
  }

  testWidgets('critério 2: continuousScroll nunca mostra alternativa '
      '(displayedPage.isAlternate sempre false)', (tester) async {
    final vc = ScoreViewController();
    final controller = ScoreController(document: doc);
    addTearDown(controller.dispose);
    await pumpAtSize(
      tester,
      view(
        doc,
        vc: vc,
        controller: controller,
        mode: ScorePageMode.continuousScroll,
      ),
      doc.pages[0].widthPx,
      doc.pages[0].heightPx,
    );
    final player = ScorePlayer(document: doc, controller: controller, view: vc);
    addTearDown(player.dispose);

    expect(vc.displayedPage.isAlternate, isFalse);
    await playToEnd(tester, player);
    expect(vc.displayedPage.isAlternate, isFalse);
    controller.clearAll();
  });

  testWidgets(
    'critério 3: seek para dentro da alternativa mostra a página certa, '
    'com a nota acesa nela',
    (tester) async {
      final vc = ScoreViewController();
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      final key = await pumpAtSize(
        tester,
        view(doc, vc: vc, controller: controller),
        doc.pages[0].widthPx,
        doc.pages[0].heightPx,
      );
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
      );
      addTearDown(player.dispose);

      final tl = ScoreTimeline(doc);
      const ms = 160000.0;
      final expectedView = tl.measures[tl.measureIndexAt(ms)].view;
      expect(expectedView.isAlternate, isTrue, reason: 'pré-condição do teste');

      player.seek(Duration(milliseconds: ms.round()));
      await tester.pump();
      expect(vc.displayedPage, expectedView);

      final noteId = tl.measures[tl.measureIndexAt(ms)].noteIds.first;
      expect(controller.isHighlighted(noteId), isTrue);
      final geometry = doc.geometryOf(expectedView.sequence);
      final ref = geometry.elementOf(noteId);
      expect(ref, isNotNull);
      expect(
        ref!.page,
        expectedView.index,
        reason: 'a nota está na página exibida',
      );

      final page = doc.pageAt(expectedView);
      final bytes = await captureBytes(
        tester,
        key,
        page.widthPx,
        page.heightPx,
      );
      final rect = geometry.rectOf(ref, pageWidth: page.widthPx.toDouble());
      expect(countRedPixels(bytes, page.widthPx, rect), greaterThan(0));
      controller.clearAll();
    },
  );

  testWidgets(
    'useAlternates: false mantém displayedPage sempre normal, tocando do '
    'início ao fim',
    (tester) async {
      final vc = ScoreViewController();
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      await pumpAtSize(
        tester,
        view(doc, vc: vc, controller: controller),
        doc.pages[0].widthPx,
        doc.pages[0].heightPx,
      );
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
        useAlternates: false,
      );
      addTearDown(player.dispose);

      expect(vc.displayedPage.isAlternate, isFalse);
      while (player.position < player.duration) {
        player.advance(const Duration(milliseconds: 200));
        await tester.pump();
        expect(vc.displayedPage.isAlternate, isFalse);
      }
      controller.clearAll();
    },
  );

  testWidgets(
    'critério 5: PictureStats.live volta a 0 depois de tocar a peça toda e '
    'desmontar',
    (tester) async {
      final vc = ScoreViewController();
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      await pumpAtSize(
        tester,
        view(doc, vc: vc, controller: controller),
        doc.pages[0].widthPx,
        doc.pages[0].heightPx,
      );
      final state = tester.state<ScoreViewState>(find.byType(ScoreView));
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
      );
      addTearDown(player.dispose);

      await playToEnd(tester, player);
      expect(state.pictureStats.live, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(state.pictureStats.live, 0);
      controller.clearAll();
    },
  );
}

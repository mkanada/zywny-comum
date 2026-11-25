// `ScoreViewCubit` (BL26; antes `ScoreViewController`): o `state` leva a página,
// a ligação da vista (`attachments`, o BG02) e as mudanças de página. As
// transições saem de uma vista de verdade, então o teste monta a `ScoreView`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_wait_turn_test.dart' show twoPages;
import 'support/render_helpers.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  Widget view(VsbDocument doc, ScoreViewCubit vc) => Directionality(
    textDirection: TextDirection.ltr,
    child: ScoreView(document: doc, viewController: vc),
  );

  testWidgets('cada ligação da vista sobe attachments e avisa, mesmo sem outra '
      'mudança (BG02)', (tester) async {
    final doc = twoPages();
    final vc = ScoreViewCubit();
    addTearDown(vc.close);
    final seen = <int>[];
    final sub = vc.stream
        .map((s) => s.attachments)
        .where((n) => n > 0)
        .distinct()
        .listen(seen.add);
    addTearDown(sub.cancel);
    final p0 = doc.pages[0];
    await pumpAtSize(tester, view(doc, vc), p0.widthPx, p0.heightPx);
    await tester.pump();
    await tester.pump();
    expect(vc.state.attachments, 1);
    expect(seen, [1]);

    await tester.pumpWidget(const SizedBox());
    await pumpAtSize(tester, view(doc, vc), p0.widthPx, p0.heightPx);
    await tester.pump();
    await tester.pump();
    expect(vc.state.attachments, 2);
    expect(seen, [1, 2]);
  });

  testWidgets('goToPage avisa a página pelo stream, uma vez por mudança', (
    tester,
  ) async {
    final doc = twoPages();
    final vc = ScoreViewCubit();
    addTearDown(vc.close);
    final p0 = doc.pages[0];
    await pumpAtSize(tester, view(doc, vc), p0.widthPx, p0.heightPx);
    await tester.pump();
    final pages = <int>[];
    final sub = vc.stream.map((s) => s.page).distinct().listen(pages.add);
    addTearDown(sub.cancel);

    vc.goToPage(1);
    vc.goToPage(1);
    await tester.pump();
    await tester.pump();
    expect(pages, [1]);
    expect(vc.currentPage, 1);
    expect(vc.displayedPage.index, 1);
  });

  testWidgets('trocar o controller da vista leva a página corrente ao novo', (
    tester,
  ) async {
    final doc = twoPages();
    final first = ScoreViewCubit();
    final second = ScoreViewCubit();
    addTearDown(first.close);
    addTearDown(second.close);
    await tester.pumpWidget(view(doc, first));
    await tester.pump();
    first.goToPage(1);
    await tester.pump();

    // A mesma árvore com outro controller: a vista troca de controller e a
    // página corrente vai junto.
    await tester.pumpWidget(view(doc, second));
    await tester.pump();
    await tester.pump();
    expect(second.isAttached, isTrue);
    expect(first.isAttached, isFalse);
    expect(second.currentPage, 1);
  });
}

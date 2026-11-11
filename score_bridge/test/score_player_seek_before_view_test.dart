// BG02 (zywny-aprendizado): o `seek` pedido antes de a vista existir (a tela
// do exercício monta a rodada e já posiciona o player na primeira nota do
// aluno, mas o `ScoreView` só nasce no quadro seguinte) tem de levar a vista
// à página dessa posição quando ela se liga, e não só quando a música toca.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_test.dart' show testPlayer;
import 'support/fake_doc.dart';
import 'support/render_helpers.dart';
import 'score_player_wait_turn_test.dart' show twoPages;

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testPlayer('seek antes de a vista existir: a página certa aparece ao ligar', (
    tester,
    cleanup,
  ) async {
    final doc = twoPages();
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: Duration.zero,
    );
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    // m3 (8000 ms) está na página 1; a vista ainda não existe.
    player.seek(const Duration(milliseconds: 8000));
    expect(vc.isAttached, isFalse);

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
    await tester.pump();
    expect(vc.currentPage, 1, reason: 'a página da posição, sem tocar nada');
  });

  // A rodada do ritmo (zywny-aprendizado) começa no instante em que a haste da
  // página começa: borda 0, que a vista não aceita. Sem haste aceita, o player
  // tem de mostrar a página dela (e não a 1) enquanto a contagem corre.
  testPlayer('seek no começo da haste (borda 0): a vista mostra a página dela', (
    tester,
    cleanup,
  ) async {
    FakeMeasure m(String id, String note) =>
        FakeMeasure(id, 100, [FakeNote(note, 120)]);
    final doc = fakeDocument(
      [
        [m('m1', 'a1'), m('m2', 'a2')],
        [m('m3', 'b1'), m('m4', 'b2')],
        [m('m5', 'c1'), m('m6', 'c2')],
      ],
      [
        (0, ['a1'], []),
        (4000, ['a2'], ['a1']),
        (8000, ['b1'], ['a2']),
        (12000, ['b2'], ['b1']),
        (16000, ['c1'], ['b2']),
        (20000, ['c2'], ['c1']),
        (24000, [], ['c2']),
      ],
    );
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: Duration.zero,
    );
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    // m4 abre a haste da página 1 (borda 0 em 12000 ms).
    player.seek(const Duration(milliseconds: 12000));
    expect(player.curtain.value?.edgeX, 0);

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
    await tester.pump();
    expect(vc.currentPage, 1, reason: 'a página da haste, sem tocar nada');
  });
}

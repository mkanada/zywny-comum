// BG02 (zywny-aprendizado): o `seek` pedido antes de a vista existir (a tela
// do exercício monta a rodada e já posiciona o player na primeira nota do
// aluno, mas o `ScoreView` só nasce no quadro seguinte) tem de levar a vista
// à página dessa posição quando ela se liga, e não só quando a música toca.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_test.dart' show testPlayer;
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
}

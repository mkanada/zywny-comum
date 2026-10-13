// Fim da rodada no meio de uma virada: `cancelTurn` tira a haste que ficou
// presa (um `pause` só congela a virada, e a vista não sai dali). Sem isso a
// partitura ficava parada no meio da animação e "Rever" não trocava de página.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  testWidgets('cancelTurn tira a haste que ficou presa no meio da virada', (
    tester,
  ) async {
    final doc = VsbDocument.fromBytes(
      Uint8List.fromList(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      ),
    );
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: Duration.zero,
    );
    try {
      final p0 = doc.pages[0];
      tester.view.physicalSize = ui.Size(
        p0.widthPx.toDouble(),
        p0.heightPx.toDouble(),
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
      );

      // No meio do último compasso da página 0: a haste para em tela (no
      // começo ou no fim do movimento ela ainda não aparece).
      final ms = player.measures;
      final i = [for (var k = 0; k + 1 < ms.length; k++) k]
          .firstWhere((k) => ms[k].page == 0 && ms[k + 1].page == 1);
      final parked = (ms[i].startMs + ms[i].endMs) / 2;

      player.seek(Duration(microseconds: (parked * 1000).round()));
      await tester.pump();
      expect(player.curtain.value, isNotNull);
      expect(vc.isTurning, isTrue, reason: 'a haste está na tela');

      player.pause();
      expect(
        player.curtain.value,
        isNotNull,
        reason: 'pausar só congela a haste',
      );

      player.cancelTurn();
      await tester.pump();
      expect(player.curtain.value, isNull);
      expect(vc.isTurning, isFalse, reason: 'sem haste presa na vista');

      // Sem a haste presa, a vista troca de página (o "Rever" da revisão).
      expect(vc.pageCount, greaterThan(1));
      final next = (vc.currentPage + 1).clamp(0, vc.pageCount - 1);
      vc.goToPage(next);
      await tester.pump();
      expect(vc.currentPage, next);
      expect(vc.isTurning, isFalse);
    } finally {
      controller.clearAll();
      player.dispose();
      controller.dispose();
      await tester.pump(const Duration(seconds: 2));
    }
  });
}

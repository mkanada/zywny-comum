// A virada de página compartilhada (`ScorePageTurn`, `ScorePager`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_comum/ui/score_paging.dart';

void main() {
  test('ScorePageTurn: parado desfoca e varre devagar', () {
    const turn = ScorePageTurn(barWidth: 10);
    expect(turn.revealBlurSigma, 20);
    expect(turn.maxSweepDuration, kDefaultMaxSweepDuration);
  });

  test('ScorePageTurn: no treino com tempo, sem desfoque e 300 ms × andamento',
      () {
    const turn = ScorePageTurn(barWidth: 10, timed: true, speed: 0.5);
    expect(turn.revealBlurSigma, 0);
    expect(turn.maxSweepDuration, const Duration(milliseconds: 150));
  });

  testWidgets('ScorePager: uma página ou tocando, nada à vista', (t) async {
    final c = ScoreViewController();
    for (final w in [
      ScorePager(controller: c, pageCount: 1),
      ScorePager(controller: c, pageCount: 3, animated: true),
    ]) {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
      expect(find.byTooltip('Próxima página'), findsNothing);
    }
  });

  testWidgets('ScorePager: antes de a vista ligar, "próxima" já vale', (t) async {
    // A vista liga ao controller depois do primeiro build, sem avisar.
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScorePager(controller: ScoreViewController(), pageCount: 3),
        ),
      ),
    );
    final next = t.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNotNull);
    await t.tap(find.byTooltip('Próxima página')); // sem vista: não lança
  });
}

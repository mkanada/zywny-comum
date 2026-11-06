// `ScorePlayer.cueFade`: a marca do player acende no instante da nota e some
// num fade fixo, qualquer que seja a duração da nota (o treino de leitura em
// tempo real usa 1 s).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  VsbDocument doc() => VsbDocument.fromBytes(
    File('test/fixtures/r13-um-compasso.vsb').readAsBytesSync(),
  );

  testWidgets('a marca some no fade fixo, antes do fim de uma nota longa', (
    tester,
  ) async {
    final document = doc();
    final controller = ScoreController(document: document);
    final player = ScorePlayer(
      document: document,
      controller: controller,
    )..cueFade = const Duration(seconds: 1);
    addTearDown(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    // m1n1 soa de 0 a 2000 ms; a marca, só o primeiro segundo.
    player.seek(Duration.zero);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.colorOf('m1n1'), isNotNull);
    await tester.pump(const Duration(milliseconds: 484));
    final half = controller.colorOf('m1n1');
    expect(half, isNotNull, reason: 'no meio do fade ainda acesa');
    expect(half, isNot(kDefaultHighlightColor), reason: 'já em fade');
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.isHighlighted('m1n1'), isFalse);
    controller.clearAll();
  });

  testWidgets('sem cueFade, a nota fica acesa até o off', (tester) async {
    final document = doc();
    final controller = ScoreController(document: document);
    final player = ScorePlayer(
      document: document,
      controller: controller,
    );
    addTearDown(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    player.seek(Duration.zero);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(controller.colorOf('m1n1'), kDefaultHighlightColor);
    controller.clearAll();
  });
}

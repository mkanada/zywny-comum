// `ScorePageCubit` (BL26): o estado de uma página (as camadas, os ids dinâmicos
// e as folhas escondidas). Uma cor num id que não é dinâmico promove o id e
// avisa (o `serial` sobe) para o pintor repintar; outra cor no mesmo id não avisa.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/colored_fixture.dart';

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);

  late VsbDocument doc;
  late ScoreCubit controller;
  late String noteId;

  setUp(() {
    doc = loadSatie();
    controller = ScoreCubit(document: doc);
    noteId = notesWithStem(doc, 0).first.id!;
  });

  tearDown(() => controller.close());

  blocTest<ScorePageCubit, ScorePageState>(
    'cor num id estático promove o id e avisa uma vez; a mesma cor não avisa',
    build: () => ScorePageCubit(
      document: doc,
      pageIndex: 0,
      controller: controller,
      animatableIds: const {},
    ),
    act: (_) {
      controller.setColor(noteId, red);
      controller.setColor(noteId, red);
    },
    expect: () => [const ScorePageState(1)],
  );

  blocTest<ScorePageCubit, ScorePageState>(
    'um id já dinâmico muda de cor sem avisar a página',
    build: () => ScorePageCubit(document: doc, pageIndex: 0, controller: controller),
    setUp: () => controller.setColor(noteId, blue),
    act: (_) => controller.setColor(noteId, red),
    expect: () => <ScorePageState>[],
  );
}

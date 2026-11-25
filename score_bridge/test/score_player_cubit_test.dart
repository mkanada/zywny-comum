// `ScorePlayer` como `Cubit` (BL26): a posição, o compasso e a haste são o
// `state`, e cada aplicação do tique avisa. Um tique que não move a posição não
// avisa nada (o `state` é igual).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'score_player_wait_turn_test.dart' show twoPages;

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late VsbDocument doc;
  late ScoreCubit controller;

  setUp(() {
    doc = twoPages();
    controller = ScoreCubit(document: doc);
  });

  tearDown(() => controller.close());

  ScorePlayer player() => ScorePlayer(
    document: doc,
    controller: controller,
    release: Duration.zero,
  );

  blocTest<ScorePlayer, ScorePlayerState>(
    'seek leva a posição e o compasso ao estado, num aviso por mudança',
    build: player,
    act: (p) => p.seek(const Duration(milliseconds: 8000)),
    verify: (p) {
      expect(p.state.positionMs, 8000);
      expect(p.state.measureIndex, 2);
      expect(p.position, const Duration(milliseconds: 8000));
    },
  );

  blocTest<ScorePlayer, ScorePlayerState>(
    'um avanço sem tempo nenhum não avisa',
    build: player,
    act: (p) => p.advance(Duration.zero),
    expect: () => <ScorePlayerState>[],
  );

  blocTest<ScorePlayer, ScorePlayerState>(
    'fechado, o player não avisa mais (e o seek não lança)',
    build: player,
    act: (p) async {
      await p.close();
      p.seek(const Duration(milliseconds: 4000));
    },
    expect: () => <ScorePlayerState>[],
  );
}

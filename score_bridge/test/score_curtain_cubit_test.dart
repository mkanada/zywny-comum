// `ScoreCurtainCubit` (BL26): a haste dirigida de fora da `ScoreView` quando não
// há um `ScorePlayer`. O estado é a própria haste; trocar pela mesma não avisa.
import 'package:bloc_test/bloc_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  const curtain = SweepCurtain(pageIndex: 0, edgeX: 40);
  const other = SweepCurtain(pageIndex: 1, edgeX: 80);

  blocTest<ScoreCurtainCubit, SweepCurtain?>(
    'show põe a haste e avisa; a mesma haste não avisa de novo',
    build: () => ScoreCurtainCubit(),
    act: (cubit) {
      cubit.show(curtain);
      cubit.show(curtain);
      cubit.show(other);
      cubit.show(null);
    },
    expect: () => [curtain, other, null],
  );
}

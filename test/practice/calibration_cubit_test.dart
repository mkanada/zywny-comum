// A rodada da calibração de latência (T04): começa parada, a contagem dos
// cliques acompanha o relógio do motor, e fechar a caixa para a rodada.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/practice_tools.dart';

import '../support/practice_fakes.dart';

void main() {
  group('CalibrationCubit', () {
    test('antes de começar: parada, sem cliques nem resultado', () {
      final cubit = CalibrationCubit(
        engine: FakeSoundEngine(),
        input: FakeMidiInput(),
      );
      addTearDown(cubit.close);

      expect(cubit.state, const CalibrationState());
    });

    test('comecar: fase tocando, e a contagem acompanha os cliques', () async {
      final engine = FakeSoundEngine();
      final input = FakeMidiInput();
      final cubit = CalibrationCubit(engine: engine, input: input);
      addTearDown(() async {
        await cubit.close();
        input.dispose();
      });

      cubit.comecar();
      expect(cubit.state.phase, CalibrationPhase.running);
      expect(cubit.state.clicksPlayed, 0);

      // Os cliques caem em 1,02 s, 1,62 s, 2,22 s… do relógio do motor.
      engine.now = 2.5;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(cubit.state.clicksPlayed, 3);
    });

    test('fechar no meio para a rodada e não emite mais', () async {
      final engine = FakeSoundEngine();
      final input = FakeMidiInput();
      final cubit = CalibrationCubit(engine: engine, input: input);
      addTearDown(input.dispose);

      cubit.comecar();
      final antes = cubit.state;
      await cubit.close();

      expect(engine.allNotesOffCalls, 1, reason: 'a rodada desligou o som');
      expect(cubit.state, antes);
      expect(cubit.isClosed, isTrue);
    });
  });
}

// O que a tela do medidor observa da rodada (LatencyMeterCubit): o andamento e o
// volume do microfone. Os métodos são síncronos; um valor igual não avisa.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/latency_meter_runner.dart';

void main() {
  group('LatencyMeterCubit', () {
    test('começa parado, sem volume', () {
      final cubit = LatencyMeterCubit();
      addTearDown(cubit.close);

      expect(cubit.state, const LatencyMeterState());
      expect(cubit.state.progress.phase, MeterPhase.idle);
      expect(cubit.state.level, 0);
    });

    test('o andamento e o volume chegam ao estado', () {
      final cubit = LatencyMeterCubit();
      addTearDown(cubit.close);

      cubit.progresso(MeterPhase.keyboard, done: 2, total: 8);
      expect(cubit.state.progress.phase, MeterPhase.keyboard);
      expect(cubit.state.progress.done, 2);
      expect(cubit.state.progress.total, 8);

      cubit.nivel(0.4);
      expect(cubit.state.level, 0.4);
    });

    test(
      'o mesmo andamento e o mesmo volume não avisam a tela de novo',
      () async {
        final cubit = LatencyMeterCubit();
        addTearDown(cubit.close);
        final avisos = <LatencyMeterState>[];
        final sub = cubit.stream.listen(avisos.add);
        addTearDown(sub.cancel);

        cubit.progresso(MeterPhase.analyzing);
        cubit.progresso(MeterPhase.analyzing);
        cubit.nivel(0.2);
        cubit.nivel(0.2);
        await pumpEventQueue();

        expect(avisos, hasLength(2));
      },
    );

    test('depois de fechado, mandar andamento ou volume não lança', () async {
      final cubit = LatencyMeterCubit();
      await cubit.close();

      expect(() {
        cubit.progresso(MeterPhase.done);
        cubit.nivel(0.1);
      }, returnsNormally);
    });
  });
}

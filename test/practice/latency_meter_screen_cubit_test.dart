// A tela do medidor por dentro (LatencyMeterScreenCubit): "Medir" faz a rodada,
// grava a medida, mostra o resultado; "Parar" interrompe; fechar para a rodada.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/latency_meter_runner.dart';
import 'package:zywny_comum/practice/latency_meter_screen.dart';

import '../support/latency_world.dart';

void main() {
  group('LatencyMeterScreenCubit', () {
    test(
      'medir: faz a rodada, grava a medida no teclado e mostra o resultado',
      () async {
        final world = LatencyWorld();
        final gravadas = <(double, bool)>[];
        final cubit = LatencyMeterScreenCubit(
          createRunner: () =>
              latencyRunner(world, speaker: LatencyWorldSpeaker(world)),
          saveLatency: (ms, corrected) async => gravadas.add((ms, corrected)),
        );
        addTearDown(cubit.close);

        await cubit.medir();

        expect(cubit.state.runner, isNull);
        expect(cubit.state.result?.failure, isNull);
        expect(gravadas, hasLength(1));
        expect(gravadas.single.$1, closeTo(45, 8));
        expect(gravadas.single.$2, isTrue);
      },
    );

    test(
      'durante a rodada, a tela tem a rodada; ao acabar, o resultado',
      () async {
        final world = LatencyWorld();
        final cubit = LatencyMeterScreenCubit(
          createRunner: () => latencyRunner(world),
          saveLatency: (ms, corrected) async {},
        );
        addTearDown(cubit.close);

        final medida = cubit.medir();
        expect(cubit.state.runner, isNotNull);
        expect(cubit.state.result, isNull);

        await medida;
        expect(cubit.state.runner, isNull);
        expect(cubit.state.result, isNotNull);
      },
    );

    test('parar: a medida sai interrompida e não grava nada', () async {
      final world = LatencyWorld();
      final gravadas = <double>[];
      final cubit = LatencyMeterScreenCubit(
        createRunner: () => latencyRunner(world),
        saveLatency: (ms, corrected) async => gravadas.add(ms),
      );
      addTearDown(cubit.close);

      final medida = cubit.medir();
      cubit.parar();
      await medida;

      expect(cubit.state.result?.failure, MeterFailure.cancelled);
      expect(gravadas, isEmpty);
    });

    test('fechar a tela no meio para a rodada e não põe resultado', () async {
      final world = LatencyWorld();
      final cubit = LatencyMeterScreenCubit(
        createRunner: () => latencyRunner(world),
        saveLatency: (ms, corrected) async {},
      );

      final medida = cubit.medir();
      await cubit.close();

      await expectLater(medida, completes);
      expect(cubit.state.result, isNull);
    });
  });
}

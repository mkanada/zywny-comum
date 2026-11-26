import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_clock/zywny_clock.dart';
import 'package:zywny_comum/app/splash_cubit.dart';

void main() {
  group('SplashState', () {
    test('copyWith troca só o campo pedido', () {
      const estado = SplashState(showing: true);

      expect(estado.copyWith(), estado);
      expect(estado.copyWith(showing: false).showing, isFalse);
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const SplashState(showing: true),
        const SplashState(showing: true),
      );
      expect(
        const SplashState(showing: true),
        isNot(const SplashState(showing: false)),
      );
    });
  });

  group('SplashCubit', () {
    test('começa cobrindo o app', () {
      final cubit = SplashCubit(
        duration: const Duration(seconds: 10),
        clock: ManualClock(DateTime(2026, 11, 25, 10)),
      );
      addTearDown(cubit.close);

      expect(cubit.state.showing, isTrue);
    });

    blocTest<SplashCubit, SplashState>(
      'hide tira a splash de cima',
      build: () => SplashCubit(
        duration: const Duration(seconds: 10),
        clock: ManualClock(DateTime(2026, 11, 25, 10)),
      ),
      act: (cubit) => cubit.hide(),
      expect: () => [const SplashState(showing: false)],
    );

    test('o tempo passa e a splash sai sozinha, no relógio dado', () {
      final relogio = ManualClock(DateTime(2026, 11, 25, 10));
      final cubit = SplashCubit(
        duration: const Duration(milliseconds: 1800),
        clock: relogio,
      );
      addTearDown(cubit.close);

      relogio.advance(const Duration(milliseconds: 1799));
      expect(cubit.state.showing, isTrue);

      relogio.advance(const Duration(milliseconds: 1));
      expect(cubit.state.showing, isFalse);
    });

    test('se fechar antes do tempo, o aviso não chega e não lança', () async {
      final relogio = ManualClock(DateTime(2026, 11, 25, 10));
      final cubit = SplashCubit(
        duration: const Duration(milliseconds: 20),
        clock: relogio,
      );

      await cubit.close();
      relogio.advance(const Duration(milliseconds: 50));

      expect(cubit.isClosed, isTrue);
      expect(
        cubit.state.showing,
        isTrue,
        reason: 'o estado não mudou depois do close',
      );
      expect(relogio.pendingTimers, isEmpty, reason: 'o timer foi cancelado');
    });
  });
}

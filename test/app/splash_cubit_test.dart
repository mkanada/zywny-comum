import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final cubit = SplashCubit(duration: const Duration(seconds: 10));
      addTearDown(cubit.close);

      expect(cubit.state.showing, isTrue);
    });

    blocTest<SplashCubit, SplashState>(
      'hide tira a splash de cima',
      build: () => SplashCubit(duration: const Duration(seconds: 10)),
      act: (cubit) => cubit.hide(),
      expect: () => [const SplashState(showing: false)],
    );

    blocTest<SplashCubit, SplashState>(
      'o tempo passa e a splash sai sozinha',
      build: () => SplashCubit(duration: const Duration(milliseconds: 10)),
      wait: const Duration(milliseconds: 60),
      expect: () => [const SplashState(showing: false)],
    );

    test('se fechar antes do tempo, o aviso não chega e não lança', () async {
      final cubit = SplashCubit(duration: const Duration(milliseconds: 20));

      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.isClosed, isTrue);
      expect(
        cubit.state.showing,
        isTrue,
        reason: 'o estado não mudou depois do close',
      );
    });
  });
}

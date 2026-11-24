// A contagem da tela (U09, count_in_overlay): a tela recebe a contagem que o
// relógio manda, e um valor igual ao anterior não avisa de novo.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/count_in_overlay.dart';

void main() {
  group('CountInCubit', () {
    test('começa sem contagem', () {
      final cubit = CountInCubit();
      addTearDown(cubit.close);

      expect(cubit.state.tick, isNull);
    });

    blocTest<CountInCubit, CountInState>(
      'mostrar põe a contagem; tirar (null) a apaga',
      build: CountInCubit.new,
      act: (cubit) {
        cubit.mostrar((remaining: 4, progress: 0.25));
        cubit.mostrar(null);
      },
      expect: () => [
        const CountInState(tick: (remaining: 4, progress: 0.25)),
        const CountInState(),
      ],
    );

    blocTest<CountInCubit, CountInState>(
      'o mesmo tempo, de novo, não avisa a tela',
      build: CountInCubit.new,
      act: (cubit) {
        cubit.mostrar((remaining: 3, progress: 0.5));
        cubit.mostrar((remaining: 3, progress: 0.5));
      },
      expect: () => [const CountInState(tick: (remaining: 3, progress: 0.5))],
    );

    test('depois de fechado, mostrar não lança', () async {
      final cubit = CountInCubit();
      await cubit.close();

      expect(() => cubit.mostrar((remaining: 1, progress: 0)), returnsNormally);
      expect(cubit.state.tick, isNull);
    });
  });
}

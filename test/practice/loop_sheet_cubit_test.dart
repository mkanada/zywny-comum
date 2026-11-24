// A folha do loop (T04): o início e o fim do trecho, presos entre 0 e o último
// compasso, e o fim nunca antes do início.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/practice_tools.dart';

void main() {
  group('LoopSheetCubit', () {
    test(
      'sem trecho escolhido: começa no compasso atual e vai ao seguinte',
      () {
        final cubit = LoopSheetCubit((total: 8, current: 2, initial: null));
        addTearDown(cubit.close);

        expect(cubit.state, const LoopSheetState(a: 2, b: 3));
      },
    );

    test('no último compasso, o fim fica nele', () {
      final cubit = LoopSheetCubit((total: 8, current: 7, initial: null));
      addTearDown(cubit.close);

      expect(cubit.state, const LoopSheetState(a: 7, b: 7));
    });

    test('um trecho já escolhido é o ponto de partida', () {
      final cubit = LoopSheetCubit((
        total: 8,
        current: 0,
        initial: (a: 4, b: 5),
      ));
      addTearDown(cubit.close);

      expect(cubit.state, const LoopSheetState(a: 4, b: 5));
    });

    blocTest<LoopSheetCubit, LoopSheetState>(
      'o início passa do fim: o fim acompanha',
      build: () =>
          LoopSheetCubit((total: 8, current: 0, initial: (a: 2, b: 3))),
      act: (cubit) => cubit.inicio(5),
      expect: () => [const LoopSheetState(a: 5, b: 5)],
    );

    blocTest<LoopSheetCubit, LoopSheetState>(
      'o fim passa para antes do início: o início acompanha',
      build: () =>
          LoopSheetCubit((total: 8, current: 0, initial: (a: 4, b: 5))),
      act: (cubit) => cubit.fim(1),
      expect: () => [const LoopSheetState(a: 1, b: 1)],
    );

    blocTest<LoopSheetCubit, LoopSheetState>(
      'os valores ficam entre 0 e o último compasso',
      build: () =>
          LoopSheetCubit((total: 8, current: 0, initial: (a: 2, b: 3))),
      act: (cubit) {
        cubit.inicio(-3);
        cubit.fim(99);
      },
      expect: () => [
        const LoopSheetState(a: 0, b: 3),
        const LoopSheetState(a: 0, b: 7),
      ],
    );

    blocTest<LoopSheetCubit, LoopSheetState>(
      'o mesmo valor, de novo, não avisa a folha',
      build: () =>
          LoopSheetCubit((total: 8, current: 0, initial: (a: 2, b: 3))),
      act: (cubit) {
        cubit.inicio(3);
        cubit.inicio(3);
      },
      expect: () => [const LoopSheetState(a: 3, b: 3)],
    );
  });
}

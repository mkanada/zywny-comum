import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/diag_screens.dart';
import 'package:zywny_diag/diag_log.dart';

void main() {
  setUp(() async {
    await DiagLog.init(storage: MemoryDiagStorage(), installHandlers: false);
  });
  tearDown(DiagLog.reset);

  group('DiagScreenState', () {
    test('é igual pelo valor (Equatable)', () {
      expect(
        const DiagScreenState(name: 'curso 3'),
        const DiagScreenState(name: 'curso 3'),
      );
      expect(
        const DiagScreenState(name: 'curso 3'),
        isNot(const DiagScreenState(name: 'curso 4')),
      );
    });
  });

  group('DiagScreenCubit', () {
    test('declara a tela aberta na construção e a tira no close', () async {
      final cubit = DiagScreenCubit(name: 'treinos');

      expect(DiagScreens.screens, ['treinos']);

      await cubit.close();

      expect(DiagScreens.screens, isEmpty);
    });

    blocTest<DiagScreenCubit, DiagScreenState>(
      'trocar o nome emite o nome novo',
      build: () => DiagScreenCubit(name: 'curso 3'),
      act: (cubit) => cubit.trocar('curso 4'),
      expect: () => [const DiagScreenState(name: 'curso 4')],
    );

    test('trocar o nome fecha a tela antiga e abre a nova', () {
      final cubit = DiagScreenCubit(name: 'curso 3');
      addTearDown(cubit.close);

      cubit.trocar('curso 4');

      expect(DiagScreens.screens, ['curso 4']);
    });

    test('trocar pelo mesmo nome não muda a lista', () {
      final cubit = DiagScreenCubit(name: 'curso 3');
      addTearDown(cubit.close);

      cubit.trocar('curso 3');

      expect(DiagScreens.screens, ['curso 3']);
      expect(cubit.state.name, 'curso 3');
    });
  });
}

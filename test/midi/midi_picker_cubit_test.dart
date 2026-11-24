import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/midi/midi_picker_cubit.dart';

void main() {
  group('MidiPickerState', () {
    test('começa sem busca e copyWith troca só o campo pedido', () {
      const estado = MidiPickerState();
      expect(estado.searching, isFalse);

      expect(estado.copyWith().searching, isFalse);
      expect(estado.copyWith(searching: true).searching, isTrue);
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const MidiPickerState(searching: true),
        const MidiPickerState(searching: true),
      );
      expect(
        const MidiPickerState(searching: true),
        isNot(equals(const MidiPickerState())),
      );
    });
  });

  group('MidiPickerCubit', () {
    blocTest<MidiPickerCubit, MidiPickerState>(
      'search liga a busca enquanto [buscar] corre e desliga no fim',
      build: () => MidiPickerCubit(buscar: () async {}),
      act: (cubit) => cubit.search(),
      expect: () => [
        const MidiPickerState(searching: true),
        const MidiPickerState(),
      ],
    );

    test('[buscar] é chamado uma vez por search', () async {
      var chamadas = 0;
      final cubit = MidiPickerCubit(
        buscar: () async {
          chamadas++;
        },
      );
      addTearDown(cubit.close);

      await cubit.search();
      await cubit.search();

      expect(chamadas, 2);
      expect(cubit.state.searching, isFalse);
    });

    test('se a busca falha, desliga a busca e repassa o erro', () async {
      final cubit = MidiPickerCubit(
        buscar: () async => throw StateError('sem permissão'),
      );
      addTearDown(cubit.close);

      await expectLater(cubit.search(), throwsA(isA<StateError>()));
      expect(cubit.state.searching, isFalse);
    });

    test(
      'se o diálogo fechar antes de a busca acabar, o fim não emite nem lança',
      () async {
        final fim = Completer<void>();
        final cubit = MidiPickerCubit(buscar: () => fim.future);

        final busca = cubit.search();
        expect(cubit.state.searching, isTrue);

        await cubit.close();
        fim.complete();

        await expectLater(busca, completes);
        expect(cubit.isClosed, isTrue);
        expect(
          cubit.state,
          const MidiPickerState(searching: true),
          reason: 'o estado ficou como estava no fechamento',
        );
      },
    );
  });
}

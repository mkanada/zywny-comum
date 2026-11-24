// As teclas apertadas (`HeldKeysCubit`, o `held` do serviço MIDI): o `state` é
// síncrono e cada troca põe um conjunto novo, para o `emit` avisar.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_midi/midi_input_service.dart';

void main() {
  group('HeldKeysCubit', () {
    _estado();
    _avisos();
  });
}

/// O `state` lido na hora, sem esperar aviso.
void _estado() {
  test('começa sem teclas, e o state se lê na hora', () {
    final cubit = HeldKeysCubit();
    addTearDown(cubit.close);

    expect(cubit.state, isEmpty);
  });

  test('apertou põe a tecla no state antes de qualquer aviso', () {
    final cubit = HeldKeysCubit();
    addTearDown(cubit.close);

    cubit.apertou(60);
    expect(cubit.state, {60});
    cubit.apertou(64);
    expect(cubit.state, {60, 64});
  });

  test('soltou tira só a tecla pedida e não muda o conjunto anterior', () {
    final cubit = HeldKeysCubit();
    addTearDown(cubit.close);
    cubit.apertou(60);
    cubit.apertou(64);
    final antes = cubit.state;

    cubit.soltou(60);

    expect(cubit.state, {64});
    expect(antes, {60, 64});
  });
}

/// Os avisos do `stream` e o Cubit fechado.
void _avisos() {
  blocTest<HeldKeysCubit, Set<int>>(
    'cada troca avisa um conjunto novo, na ordem das teclas',
    build: HeldKeysCubit.new,
    act: (cubit) {
      cubit.apertou(60);
      cubit.apertou(64);
      cubit.soltou(60);
    },
    expect: () => [
      {60},
      {60, 64},
      {64},
    ],
  );

  blocTest<HeldKeysCubit, Set<int>>(
    'soltar uma tecla que não está apertada ainda avisa, com o conjunto vazio',
    build: HeldKeysCubit.new,
    act: (cubit) => cubit.soltou(60),
    expect: () => [<int>{}],
  );

  test('fechado, o state continua legível e nada mais é avisado', () async {
    final cubit = HeldKeysCubit();
    cubit.apertou(60);
    await cubit.close();

    expect(cubit.state, {60});
    expect(() => cubit.apertou(64), throwsStateError);
  });
}

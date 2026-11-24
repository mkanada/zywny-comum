import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/midi/midi_monitor_cubit.dart';
import 'package:zywny_midi/midi_input_service.dart';

PlayedNote _nota(int tom, {bool on = true}) => PlayedNote(
  pitch: tom,
  velocity: 90,
  channel: 0,
  on: on,
  atSeconds: tom / 10,
);

void main() {
  group('MidiMonitorState', () {
    test('começa sem mensagens e copyWith troca só a lista', () {
      const estado = MidiMonitorState();
      expect(estado.messages, isEmpty);

      final nota = _nota(60);
      expect(estado.copyWith().messages, isEmpty);
      expect(estado.copyWith(messages: [nota]).messages, [nota]);
    });

    test('é igual pela lista (Equatable)', () {
      final nota = _nota(60);
      expect(
        MidiMonitorState(messages: [nota]),
        equals(MidiMonitorState(messages: [nota])),
      );
      expect(
        MidiMonitorState(messages: [nota]),
        isNot(equals(const MidiMonitorState())),
      );
    });
  });

  group('MidiMonitorCubit', () {
    late StreamController<PlayedNote> notas;
    late PlayedNote primeira;
    late PlayedNote segunda;
    late PlayedNote terceira;

    setUp(() {
      notas = StreamController<PlayedNote>.broadcast(sync: true);
      primeira = _nota(60);
      segunda = _nota(62);
      terceira = _nota(64);
    });

    tearDown(() => notas.close());

    test('começa sem mensagens, antes de qualquer nota', () {
      final cubit = MidiMonitorCubit(notes: notas.stream, limite: 20);
      addTearDown(cubit.close);

      expect(cubit.state, const MidiMonitorState());
    });

    blocTest<MidiMonitorCubit, MidiMonitorState>(
      'cada nota que chega entra na frente, e o limite corta a mais antiga',
      build: () => MidiMonitorCubit(notes: notas.stream, limite: 2),
      act: (_) {
        notas.add(primeira);
        notas.add(segunda);
        notas.add(terceira);
      },
      expect: () => [
        MidiMonitorState(messages: [primeira]),
        MidiMonitorState(messages: [segunda, primeira]),
        MidiMonitorState(messages: [terceira, segunda]),
      ],
    );

    test('com o limite de 20, de 25 notas ficam só as 20 últimas', () {
      final cubit = MidiMonitorCubit(notes: notas.stream, limite: 20);
      addTearDown(cubit.close);

      for (var i = 0; i < 25; i++) {
        notas.add(_nota(40 + i));
      }

      final mensagens = cubit.state.messages;
      expect(mensagens, hasLength(20));
      expect(mensagens.first.pitch, 64, reason: 'a última nota vem primeiro');
      expect(mensagens.last.pitch, 45, reason: 'a 6.ª nota é a mais antiga');
    });

    test(
      'depois de fechar, a escuta para: nota nova não muda nem lança',
      () async {
        final cubit = MidiMonitorCubit(notes: notas.stream, limite: 20);
        notas.add(primeira);
        expect(cubit.state.messages, [primeira]);

        await cubit.close();
        expect(cubit.isClosed, isTrue);

        expect(() => notas.add(segunda), returnsNormally);
        expect(cubit.state.messages, [primeira]);
      },
    );
  });
}

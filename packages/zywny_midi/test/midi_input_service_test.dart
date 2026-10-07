// Testes de parsing/normalização do M01 (critério de aceite 4): mensagens
// sintéticas, sem tocar em MidiCommand/canal de plataforma nenhum —
// `FlutterMidiInputService` aceita o stream de eventos por injeção
// exatamente para isto.

import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_midi/midi_input_service.dart';

FlutterMidiInputService _service({double Function()? nowSeconds}) =>
    FlutterMidiInputService(
      nowSeconds: nowSeconds ?? () => 0,
      events: const Stream<MidiDataReceivedEvent>.empty(),
    );

void main() {
  group(
    'MidiMessage.parse (flutter_midi_command) — o que o serviço recebe',
    () {
      test('running status: só o 1º Note On leva o status byte', () {
        final messages = MidiMessage.parse(
          Uint8List.fromList([0x90, 60, 100, 62, 80, 64, 90]),
        );
        expect(messages, hasLength(3));
        expect(messages[0], isA<NoteOnMessage>());
        expect((messages[0] as NoteOnMessage).note, 60);
        expect((messages[1] as NoteOnMessage).note, 62);
        expect((messages[2] as NoteOnMessage).note, 64);
      });

      test('note-on com velocity 0 vira NoteOffMessage (running status)', () {
        final messages = MidiMessage.parse(
          Uint8List.fromList([0x90, 60, 100, 60, 0]),
        );
        expect(messages, hasLength(2));
        expect(messages[0], isA<NoteOnMessage>());
        expect(messages[1], isA<NoteOffMessage>());
        expect((messages[1] as NoteOffMessage).note, 60);
      });

      test('CC64 (sustain) é reconhecido', () {
        final messages = MidiMessage.parse(Uint8List.fromList([0xB0, 64, 127]));
        expect(messages, hasLength(1));
        final cc = messages.single as CCMessage;
        expect(cc.controller, 64);
        expect(cc.value, 127);
      });
    },
  );

  group('FlutterMidiInputService.handleMessage', () {
    test('Note On vira PlayedNote(on: true) e entra em held', () async {
      final service = _service(nowSeconds: () => 1.5);
      final future = service.notes.first;
      service.handleMessage(
        NoteOnMessage(channel: 2, note: 60, velocity: 100),
        atSeconds: 1.5,
      );
      final note = await future;
      expect(note.pitch, 60);
      expect(note.velocity, 100);
      expect(note.channel, 2);
      expect(note.on, isTrue);
      expect(note.atSeconds, 1.5);
      expect(service.held.value, {60});
      service.dispose();
    });

    test('Note Off remove de held', () async {
      final service = _service();
      service.handleMessage(
        NoteOnMessage(note: 60, velocity: 100),
        atSeconds: 0,
      );
      expect(service.held.value, {60});
      service.handleMessage(
        NoteOffMessage(note: 60, velocity: 0),
        atSeconds: 1,
      );
      expect(service.held.value, isEmpty);
      service.dispose();
    });

    test('Note On com velocity 0 é normalizado para nota desligada mesmo se '
        'chegar como NoteOnMessage (defesa própria do serviço, não só do '
        'parser do plugin)', () async {
      final service = _service();
      final future = service.notes.first;
      service.handleMessage(NoteOnMessage(note: 60, velocity: 0), atSeconds: 0);
      final note = await future;
      expect(note.on, isFalse);
      expect(service.held.value, isEmpty);
      service.dispose();
    });

    test('CC64 publica em sustain; outros CCs são ignorados', () async {
      final service = _service();
      final sustainValues = <int>[];
      final sub = service.sustain.listen(sustainValues.add);

      service.handleMessage(
        CCMessage(controller: 64, value: 127),
        atSeconds: 0,
      );
      service.handleMessage(
        CCMessage(controller: 7, value: 90), // volume — fora de escopo
        atSeconds: 0,
      );
      await Future<void>.delayed(Duration.zero);

      expect(sustainValues, [127]);
      expect(service.held.value, isEmpty);
      await sub.cancel();
      service.dispose();
    });

    test('duas notas seguradas ao mesmo tempo aparecem juntas em held', () {
      final service = _service();
      service.handleMessage(
        NoteOnMessage(note: 60, velocity: 100),
        atSeconds: 0,
      );
      service.handleMessage(
        NoteOnMessage(note: 64, velocity: 90),
        atSeconds: 0,
      );
      expect(service.held.value, {60, 64});
      service.handleMessage(
        NoteOffMessage(note: 60, velocity: 0),
        atSeconds: 0,
      );
      expect(service.held.value, {64});
      service.dispose();
    });
  });
}

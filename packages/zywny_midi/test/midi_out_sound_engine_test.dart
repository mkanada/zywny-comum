// M03: `MidiOutSoundEngine` com um `FakeMidiSender` que só registra o que foi
// mandado — sem canal de plataforma de verdade, tempo simulado avançando
// `now` e chamando `pump()` direto (`autoTick: false`), no mesmo estilo de
// test/score_audio_scheduler_test.dart (K04).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_midi/midi_out_sound_engine.dart';

class SentMidiMessage {
  SentMidiMessage(this.bytes, this.deviceId, this.atSeconds);

  final List<int> bytes;
  final String? deviceId;
  final double atSeconds;
}

class FakeMidiSender implements MidiSender {
  double now = 0;
  final List<SentMidiMessage> sent = [];

  @override
  void send(Uint8List data, {String? deviceId}) {
    sent.add(SentMidiMessage(List<int>.unmodifiable(data), deviceId, now));
  }
}

void main() {
  group('MidiOutSoundEngine', () {
    test('despacha em ordem de "at", só quando now alcança at - lead', () {
      final sender = FakeMidiSender();
      final engine = MidiOutSoundEngine(
        sender: sender,
        deviceId: 'dev-1',
        nowSeconds: () => sender.now,
        autoTick: false,
      );

      // Fora de ordem de chamada, mas "at" crescente é o que importa.
      engine.schedule([
        const ScheduledMidi(0.100, 0x90, 60, 100),
        const ScheduledMidi(0.050, 0x90, 64, 100),
      ]);
      engine.schedule([const ScheduledMidi(0.052, 0x80, 64, 0)]);

      sender.now = 0.010;
      engine.pump();
      expect(sender.sent, isEmpty, reason: 'nada chegou ainda');

      // 0.050 - lead (0.002) = 0.048.
      sender.now = 0.048;
      engine.pump();
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.bytes, [0x90, 64, 100]);
      expect(sender.sent.single.deviceId, 'dev-1');

      sender.now = 0.052;
      engine.pump();
      expect(sender.sent, hasLength(2));
      expect(sender.sent[1].bytes, [0x80, 64, 0]);

      sender.now = 0.200;
      engine.pump();
      expect(sender.sent, hasLength(3));
      expect(sender.sent[2].bytes, [0x90, 60, 100]);
    });

    test(
      'allNotesOff desliga exatamente as teclas ligadas e limpa a agenda',
      () {
        final sender = FakeMidiSender();
        final engine = MidiOutSoundEngine(
          sender: sender,
          deviceId: 'dev-1',
          nowSeconds: () => sender.now,
          autoTick: false,
        );

        engine.schedule([
          const ScheduledMidi(0, 0x90, 60, 100), // liga e nunca desliga
          const ScheduledMidi(0, 0x91, 62, 100), // canal 1, liga e desliga
          const ScheduledMidi(0, 0x81, 62, 0),
        ]);
        // Um evento que ainda nem chegou: allNotesOff deve descartá-lo.
        engine.schedule([const ScheduledMidi(10, 0x90, 67, 100)]);

        sender.now = 1;
        engine.pump();
        expect(sender.sent, hasLength(3));

        engine.allNotesOff();

        final noteOffs = sender.sent
            .skip(3)
            .where((m) => m.bytes[0] & 0xF0 == 0x80)
            .toList();
        // Só a tecla 60 (canal 0) ainda estava ligada — 62 já tinha recebido
        // note-off antes do allNotesOff.
        expect(noteOffs, hasLength(1));
        expect(noteOffs.single.bytes, [0x80, 60, 0]);

        final ccByController = <int, List<SentMidiMessage>>{};
        for (final m in sender.sent.skip(4)) {
          ccByController.putIfAbsent(m.bytes[1], () => []).add(m);
        }
        // CC123/120/64 em cada um dos 16 canais.
        expect(ccByController[123], hasLength(16));
        expect(ccByController[120], hasLength(16));
        expect(ccByController[64], hasLength(16));

        // A nota agendada para o futuro (10s) não deveria ter sido descartada
        // silenciosamente sem nunca soar: ela nunca chegou a soar, então não
        // deve gerar mensagem nenhuma quando o tempo avançar.
        sender.now = 20;
        engine.pump();
        expect(sender.sent, hasLength(4 + 16 * 3));
      },
    );

    test('Program Change só sai com useScoreInstruments ligado', () {
      final sender = FakeMidiSender();
      final engine = MidiOutSoundEngine(
        sender: sender,
        deviceId: 'dev-1',
        nowSeconds: () => sender.now,
        autoTick: false,
      );

      engine.schedule([const ScheduledMidi(0, 0xC0, 5, 0)]);
      engine.pump();
      expect(sender.sent, isEmpty, reason: 'padrão é não mandar PC');

      engine.useScoreInstruments = true;
      engine.schedule([const ScheduledMidi(0, 0xC1, 5, 0)]);
      engine.pump();
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.bytes, [0xC1, 5, 0]);

      sender.sent.clear();
      engine.send([0xC0, 7, 0]);
      expect(sender.sent, hasLength(1));
    });

    test('forceChannel1 remapeia o canal de saída para o canal 1', () {
      final sender = FakeMidiSender();
      final engine = MidiOutSoundEngine(
        sender: sender,
        deviceId: 'dev-1',
        nowSeconds: () => sender.now,
        forceChannel1: true,
        autoTick: false,
      );

      engine.schedule([const ScheduledMidi(0, 0x93, 60, 100)]);
      engine.pump();
      expect(sender.sent.single.bytes[0], 0x90);

      engine.send([0x84, 60, 0]);
      expect(sender.sent.last.bytes[0], 0x80);
    });

    test('send() imediato, sem passar pela fila', () {
      final sender = FakeMidiSender();
      final engine = MidiOutSoundEngine(
        sender: sender,
        deviceId: 'dev-1',
        nowSeconds: () => sender.now,
        autoTick: false,
      );

      engine.send([0x90, 60, 100]);
      expect(sender.sent, hasLength(1));

      // allNotesOff também desliga o que entrou via send() direto.
      engine.allNotesOff();
      final explicitOff = sender.sent
          .skip(1)
          .where((m) => m.bytes[0] == 0x80 && m.bytes[1] == 60)
          .toList();
      expect(explicitOff, hasLength(1));
    });
  });
}

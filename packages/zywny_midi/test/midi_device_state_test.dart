// O estado do gerenciador de teclados (`MidiDeviceState`): o `copyWith` troca
// só o campo pedido, e a função de um campo anulável é o que põe `null`.

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_midi/midi_device_manager.dart';

void main() {
  final piano = MidiDevice('a', 'Piano', MidiDeviceType.serial, false);

  group('MidiDeviceState', () {
    test('começa sem teclado, sem erro e com o MIDI acessível', () {
      const estado = MidiDeviceState();

      expect(estado.devices, isEmpty);
      expect(estado.connected, isNull);
      expect(estado.lastError, isNull);
      expect(estado.unavailable, isNull);
      expect(estado.bluetoothNote, isNull);
    });

    test('copyWith sem argumentos é igual ao original', () {
      final estado = MidiDeviceState(devices: [piano], connected: piano);

      expect(estado.copyWith(), estado);
    });

    test('copyWith troca só o campo pedido', () {
      final estado = MidiDeviceState(devices: [piano], lastError: 'falhou');
      final trocado = estado.copyWith(connected: () => piano);

      expect(trocado.connected, piano);
      expect(trocado.lastError, 'falhou');
      expect(trocado.devices, [piano]);
    });

    test('a função de um campo anulável põe null', () {
      final estado = MidiDeviceState(connected: piano, bluetoothNote: 'x');
      final limpo = estado.copyWith(
        connected: () => null,
        bluetoothNote: () => null,
      );

      expect(limpo.connected, isNull);
      expect(limpo.bluetoothNote, isNull);
    });

    test('o motivo de a lista não existir sai com copyWith', () {
      const estado = MidiDeviceState();
      final negado = estado.copyWith(unavailable: () => MidiUnavailable.denied);

      expect(negado.unavailable, MidiUnavailable.denied);
      expect(negado.copyWith(unavailable: () => null).unavailable, isNull);
    });
  });
}

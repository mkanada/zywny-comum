import 'package:flutter_midi_command/flutter_midi_command.dart';

/// O tipo do aparelho em português, no lugar do nome do protocolo ("native",
/// "own-virtual"…). Vazio quando não há o que dizer (`unknown`).
String midiDeviceTypeLabel(MidiDeviceType type) => switch (type) {
  MidiDeviceType.serial => 'USB',
  MidiDeviceType.ble => 'Bluetooth',
  MidiDeviceType.network => 'Rede',
  MidiDeviceType.virtual || MidiDeviceType.ownVirtual => 'Virtual',
  MidiDeviceType.unknown => '',
};

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lista dispositivos MIDI, conecta, guarda o último escolhido e reconecta
/// sozinho a ele — na abertura do app e a cada hot-plug (M01, critério de
/// aceite 1). Não decodifica mensagens: isso é `MidiInputService`.
class MidiDeviceManager {
  MidiDeviceManager({MidiCommand? midi, SharedPreferencesAsync? prefs})
    : _midi = midi ?? MidiCommand(),
      _prefs = prefs ?? SharedPreferencesAsync() {
    _setupSub = _midi.onMidiSetupChanged?.listen((_) => refresh());
    unawaited(refresh());
  }

  static const _kLastDeviceIdKey = 'midi_last_device_id';

  final MidiCommand _midi;
  final SharedPreferencesAsync _prefs;
  StreamSubscription<MidiSetupChange>? _setupSub;

  final ValueNotifier<List<MidiDevice>> devices = ValueNotifier(const []);
  final ValueNotifier<MidiDevice?> connected = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Relista os dispositivos e, se nada estiver conectado, tenta reconectar
  /// ao último escolhido (persistido). Chamado na abertura do serviço e a
  /// cada `onMidiSetupChanged` (plugue/desplugue).
  Future<void> refresh() async {
    final list = await _midi.devices ?? const <MidiDevice>[];
    devices.value = list;

    final current = connected.value;
    if (current != null && !list.any((d) => d.id == current.id)) {
      connected.value = null;
    }

    if (connected.value != null) return;
    final lastId = await _prefs.getString(_kLastDeviceIdKey);
    if (lastId == null) return;
    MidiDevice? match;
    for (final d in list) {
      if (d.id == lastId) {
        match = d;
        break;
      }
    }
    if (match != null && !match.connected) {
      await connect(match);
    }
  }

  Future<void> connect(MidiDevice device) async {
    try {
      await _midi.connectToDevice(device);
      connected.value = device;
      lastError.value = null;
      await _prefs.setString(_kLastDeviceIdKey, device.id);
    } on MidiConnectionException catch (e) {
      lastError.value = e.toString();
    }
  }

  void disconnect() {
    final device = connected.value;
    if (device == null) return;
    _midi.disconnectDevice(device);
    connected.value = null;
  }

  void dispose() {
    unawaited(_setupSub?.cancel());
    devices.dispose();
    connected.dispose();
    lastError.dispose();
  }
}

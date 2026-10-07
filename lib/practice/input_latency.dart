// I09 — ler a latência calibrada fora da `ScoreHomePage` (partitura e tela
// do exercício). Saiu de `audio/engine_opener.dart` no R03: depende de MIDI e
// das configurações, que o áudio não importa.

import '../midi/midi_device_manager.dart';
import '../settings/app_settings.dart';

/// A chave da latência calibrada por par (dispositivo, saída): `'app'` ou
/// `'midi'` — o mesmo `_outputKey` de `main.dart`.
String soundOutputKey(SoundOutput output) =>
    output == SoundOutput.midiKeyboard ? 'midi' : 'app';

/// Latência de entrada+saída calibrada (ms) para o dispositivo e a saída
/// correntes; 0 sem dispositivo ou sem calibração. Extração fiel do
/// `_loadInputLatency` de `main.dart`.
Future<double> calibratedInputLatency(
  MidiDeviceManager devices,
  SoundOutput output,
) async {
  final device = devices.connected.value;
  if (device == null) return 0;
  return await devices.inputLatencyMs(device.id, soundOutputKey(output)) ?? 0;
}

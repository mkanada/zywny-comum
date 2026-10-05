// I09 — o mínimo de `main.dart` para abrir som fora da `ScoreHomePage`:
// abrir o motor do app e ler a latência calibrada. Usado pela partitura e
// pela tela do exercício (risco 4 do I00: o exercício NÃO mora em `main.dart`).

import '../midi/midi_device_manager.dart';
import '../settings/app_settings.dart';
import 'sound_engine.dart';
import 'sound_engine_factory.dart';
import 'soundfont_store.dart';

/// Abre o sintetizador do app (`.sf2` do usuário ou o embutido); `null` se o
/// motor não abriu. Extração fiel do `_pickEngineWithSoundFont` de `main.dart`.
Future<SoundEngine?> openAppSoundEngine({
  SoundFontStore soundFonts = const SoundFontStore(),
}) async {
  final engine = createSoundEngine();
  await engine.start();
  await engine.loadSoundFont(await soundFonts.load());
  return engine;
}

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

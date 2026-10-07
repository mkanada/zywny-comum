// I09 — o mínimo de `main.dart` para abrir som fora da `ScoreHomePage`:
// abrir o motor do app. Usado pela partitura e pela biblioteca (risco 4 do
// I00: o exercício NÃO mora em `main.dart`). A latência calibrada fica em
// `practice/input_latency.dart` (R03: o áudio não importa MIDI nem settings).

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

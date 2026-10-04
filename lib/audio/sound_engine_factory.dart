import 'sound_engine.dart';
import '_native.dart' if (dart.library.js_interop) '_web.dart' as impl;

/// Cria a implementação de [SoundEngine] certa para esta plataforma: nativa
/// (`dart:ffi`, K02) fora da Web, e na Web (W04) o SpessaSynth num
/// AudioWorklet (`WebSoundEngine`).
SoundEngine createSoundEngine() => impl.createSoundEngine();

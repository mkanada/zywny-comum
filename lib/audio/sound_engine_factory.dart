import 'sound_engine.dart';
import '_stub.dart' if (dart.library.io) '_native.dart' as impl;

/// Cria a implementação de [SoundEngine] certa para esta plataforma: nativa
/// (`dart:ffi`, K02) fora da Web; na Web (W04) o stub lança
/// `UnsupportedError` até aquele passo trazer a implementação de verdade.
SoundEngine createSoundEngine() => impl.createSoundEngine();

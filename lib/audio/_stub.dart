import 'sound_engine.dart';

/// A Web (W04) ainda não tem motor de som — aquele passo substitui isto por
/// uma implementação de verdade (Web Audio).
SoundEngine createSoundEngine() => throw UnsupportedError(
  'SoundEngine não implementado nesta plataforma ainda (W04 traz a Web)',
);

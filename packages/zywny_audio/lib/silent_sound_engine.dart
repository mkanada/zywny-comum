import 'dart:typed_data';

import 'package:zywny_clock/zywny_clock.dart';

import 'sound_engine.dart';

/// O motor do "Som" desligado: não toca nem manda nada para fora, mas tem
/// relógio e aceita as agendas como os outros motores. Assim a partitura, o
/// exercício e o ouvido seguem o mesmo caminho, e só o que sairia pelo som
/// fica de fora.
///
/// O relógio é o do app ([AppClock], CT05b), passado pelo construtor: o motor
/// mudo não tem relógio de dispositivo, então o tempo dele é o que o app manda
/// (o roteiro de capturas põe o `ManualClock`). Os motores de verdade seguem no
/// relógio do áudio.
class SilentSoundEngine implements SoundEngine {
  SilentSoundEngine({required this.clock});

  /// O relógio que o app deu ao motor (o do `main` ou o do roteiro).
  final AppClock clock;

  @override
  double get nowSeconds => clock.seconds;

  @override
  double get earliestScheduleSeconds => nowSeconds;

  @override
  double get outputLatencySeconds => 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}

  @override
  void send(List<int> midi) {}

  @override
  void schedule(List<ScheduledMidi> events) {}

  @override
  void clearScheduled() {}

  @override
  void allNotesOff() {}

  @override
  Future<void> dispose() async {}
}

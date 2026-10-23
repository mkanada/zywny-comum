import 'dart:typed_data';

import 'sound_engine.dart';

/// O motor do "Som" desligado: não toca nem manda nada para fora, mas tem
/// relógio e aceita as agendas como os outros motores. Assim a partitura, o
/// exercício e o ouvido seguem o mesmo caminho, e só o que sairia pelo som
/// fica de fora.
class SilentSoundEngine implements SoundEngine {
  SilentSoundEngine({double Function()? nowSeconds})
    : _nowSeconds = nowSeconds ?? _stopwatchClock();

  /// Um `Stopwatch` do app, como o do teclado MIDI de saída (que também não
  /// tem relógio de dispositivo).
  static double Function() _stopwatchClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds / 1e6;
  }

  final double Function() _nowSeconds;

  @override
  double get nowSeconds => _nowSeconds();

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

// O "Som" desligado: o motor mudo tem relógio que anda e aceita as agendas
// sem tocar nada (a partitura e o exercício seguem o mesmo caminho).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/silent_sound_engine.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_clock/zywny_clock.dart';

void main() {
  test('o relógio é o do app e anda com ele (ManualClock)', () {
    final relogio = ManualClock(DateTime(2026));
    final engine = SilentSoundEngine(clock: relogio);
    expect(engine.nowSeconds, 0);
    expect(engine.earliestScheduleSeconds, 0);
    relogio.advance(const Duration(milliseconds: 1500));
    expect(engine.nowSeconds, 1.5);
    expect(engine.earliestScheduleSeconds, 1.5);
    relogio.advance(const Duration(milliseconds: 750));
    expect(engine.nowSeconds, 2.25);
  });

  test('com o SystemClock, o tempo do motor anda de verdade', () async {
    final engine = SilentSoundEngine(clock: SystemClock());
    final before = engine.nowSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(engine.nowSeconds, greaterThan(before));
  });

  test('agendar, mandar e desligar não fazem nada e não jogam', () async {
    final engine = SilentSoundEngine(clock: ManualClock(DateTime(2026)));
    await engine.start();
    await engine.loadSoundFont(Uint8List(0));
    engine.send([0x90, 60, 100]);
    engine.schedule([const ScheduledMidi(0.5, 0x90, 60, 100)]);
    engine.clearScheduled();
    engine.allNotesOff();
    await engine.dispose();
    expect(engine.outputLatencySeconds, 0);
  });
}

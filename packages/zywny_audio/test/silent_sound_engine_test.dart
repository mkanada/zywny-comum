// O "Som" desligado: o motor mudo tem relógio que anda e aceita as agendas
// sem tocar nada (a partitura e o exercício seguem o mesmo caminho).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/silent_sound_engine.dart';
import 'package:zywny_audio/sound_engine.dart';

void main() {
  test('o relógio vem da função dada e anda com ela', () {
    var t = 1.5;
    final engine = SilentSoundEngine(nowSeconds: () => t);
    expect(engine.nowSeconds, 1.5);
    expect(engine.earliestScheduleSeconds, 1.5);
    t = 2.25;
    expect(engine.nowSeconds, 2.25);
  });

  test('sem relógio dado, o tempo sai de um cronômetro do app', () async {
    final engine = SilentSoundEngine();
    final before = engine.nowSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(engine.nowSeconds, greaterThan(before));
  });

  test('agendar, mandar e desligar não fazem nada e não jogam', () async {
    final engine = SilentSoundEngine(nowSeconds: () => 0);
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

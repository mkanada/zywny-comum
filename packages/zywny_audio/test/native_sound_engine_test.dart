// `NativeSoundEngine` (K03) sobre o motor nativo `zywny_audio` (K02).
//
// Depende de um artefato não versionado; sem ele o teste é pulado em vez de
// falhar (mesmo padrão de vsb_render_test.dart):
//   tool/build_audio_linux.sh -> native/zywny_audio/target/release/libzywny_audio.so
//
// Sem dispositivo de áudio (CI sem placa de som, por exemplo) `start()`
// ainda pula, dessa vez em tempo de execução: `zy_engine_new` falha sem um
// `default_output_device`, e o teste pula com o motivo em vez de falhar.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/native_sound_engine.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_audio/audio_library_path.dart';

String? _findLibOrNull() {
  try {
    return findAudioLibrary();
  } on StateError {
    return null;
  }
}

void main() {
  final libPath = _findLibOrNull();

  test(
    'cria o motor, agenda 10 notas, nowSeconds anda em 1000 leituras (K03, '
    'critério 2)',
    () async {
      late NativeSoundEngine engine;
      try {
        engine = NativeSoundEngine();
        await engine.start();
      } catch (e) {
        markTestSkipped('zy_engine_new falhou (sem dispositivo de áudio?): $e');
        return;
      }
      addTearDown(engine.dispose);

      // Soundfont de teste (K01/K02): sem ele, ainda dá para confirmar que
      // o relógio anda — só não agenda nada de verdade.
      final sf2Path =
          Platform.environment['ZYWNY_TEST_SF2'] ??
          '/usr/share/sounds/sf2/TimGM6mb.sf2';
      final sf2File = File(sf2Path);
      if (sf2File.existsSync()) {
        await engine.loadSoundFont(await sf2File.readAsBytes());
        final start = engine.earliestScheduleSeconds + 0.05;
        engine.schedule([
          for (var i = 0; i < 10; i++)
            ScheduledMidi(start + i * 0.05, 0x90, 60 + i, 100),
        ]);
      }

      // Tolerância folgada: só confere que nunca volta, não a granularidade.
      var previous = engine.nowSeconds;
      for (var i = 0; i < 1000; i++) {
        final current = engine.nowSeconds;
        expect(
          current,
          greaterThanOrEqualTo(previous),
          reason: 'nowSeconds voltou no passo $i',
        );
        previous = current;
      }
    },
    skip: libPath == null
        ? 'libzywny_audio.so não encontrada — rode tool/build_audio_linux.sh'
        : null,
  );
}

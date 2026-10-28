// EX07: a gravação da execução (lib/practice/performance_capture.dart), sem
// MIDI: as teclas e o pedal entram com a hora que a quem chama dá.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/performance_capture.dart';

void main() {
  group('PerformanceCapture', () {
    test('o fim da tecla fecha a nota que foi apertada, pela altura', () {
      final capture = PerformanceCapture();
      final index = capture.noteOn(60, 72, 1000);

      expect(capture.noteAt(index).offMs, isNull);
      capture.noteOff(60, 1450);

      final note = capture.noteAt(index);
      expect(note.pitch, 60);
      expect(note.velocity, 72);
      expect(note.onMs, 1000);
      expect(note.offMs, 1450);
    });

    test('notas saem em ordem de ataque, mesmo gravadas fora de ordem', () {
      final capture = PerformanceCapture();
      capture.noteOn(64, 80, 500);
      capture.noteOn(60, 80, 100);
      capture.noteOff(64, 700);
      capture.noteOff(60, 300);

      expect(capture.notes.map((n) => n.pitch), [60, 64]);
    });

    test('fim de uma tecla que não foi gravada é ignorado', () {
      final capture = PerformanceCapture();
      capture.noteOff(60, 300);

      expect(capture.notes, isEmpty);
    });

    test(
      'a mesma altura apertada de novo deixa o ataque anterior em aberto',
      () {
        final capture = PerformanceCapture();
        final first = capture.noteOn(60, 80, 0);
        final second = capture.noteOn(60, 80, 400);
        capture.noteOff(60, 600);

        expect(capture.noteAt(first).offMs, isNull);
        expect(capture.noteAt(second).offMs, 600);
      },
    );

    test('o pedal fica abaixado a partir de 64, e sai em ordem de tempo', () {
      final capture = PerformanceCapture();
      capture.pedal(127, 900);
      capture.pedal(63, 200);
      capture.pedal(64, 500);

      expect(capture.pedals.map((p) => p.atMs), [200, 500, 900]);
      expect(capture.pedals.map((p) => p.down), [false, true, true]);
    });

    test('clear esvazia tudo, e a altura presa antes não fecha depois', () {
      final capture = PerformanceCapture();
      capture.noteOn(60, 80, 0);
      capture.pedal(127, 0);
      capture.clear();
      capture.noteOff(60, 100);

      expect(capture.notes, isEmpty);
      expect(capture.pedals, isEmpty);
    });
  });
}

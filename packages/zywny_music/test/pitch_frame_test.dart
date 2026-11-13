// Q02, critério 1 — `PitchFrame`: a tabela de verdade das quatro conversões
// (docs/plano/Q00, "O problema do MIDI do teclado") nos 2 × 2 casos de teclado,
// e o caminho de sempre (k = 0) sem custo.

import 'package:test/test.dart';
import 'package:zywny_music/pitch_frame.dart';
import 'package:zywny_music/transposition.dart';

const k = -3;
const written = 60;
const sounding = 63;

/// Com `k = 0` o teclado não muda nada, com ou sem `appIsSound`.
void _zeroIgnoraTeclado(bool out, bool inn) {
  for (final app in [false, true]) {
    final frame = PitchFrame(
      0,
      keyboardShiftsOut: out,
      keyboardShiftsIn: inn,
      appIsSound: app,
    );
    expect(frame.isIdentity, isTrue);
    expect(frame.writtenFromReceived(60), 60);
    expect(frame.soundingFromWritten(60), 60);
    expect(frame.monitorFromReceived(60), 60);
    expect(frame.outFromWritten(60), 60);
  }
}

void main() {
  _parte5();
  _parte6();
  _parte7();
}

void _parte1() {
  test('o teclado que transpõe a saída MIDI manda a soada (63)', () {
    const frame = PitchFrame(k, keyboardShiftsOut: true);
    // casador: soma k e volta à escrita
    expect(frame.writtenFromReceived(63), written);
    // monitor: a recebida já é a soada
    expect(frame.monitorFromReceived(63), sounding);
  });
  test('o teclado que só muda o som interno manda a escrita (60)', () {
    const frame = PitchFrame(k);
    expect(frame.writtenFromReceived(60), written);
    // monitor: soma −k à escrita
    expect(frame.monitorFromReceived(60), sounding);
  });
  test('o agendador e os motores tocam a soada da escrita', () {
    for (final out in [false, true]) {
      for (final inn in [false, true]) {
        final frame = PitchFrame(
          k,
          keyboardShiftsOut: out,
          keyboardShiftsIn: inn,
        );
        expect(frame.soundingFromWritten(written), sounding);
      }
    }
  });
  test('à saída para o teclado: a soada, ou a escrita se ele transpõe', () {
    // Não transpõe a entrada: manda a soada (63) e o teclado toca o 63.
    expect(const PitchFrame(k).outFromWritten(written), sounding);
    // Transpõe a entrada (TRANSPOSE +3 soma 3 ao que recebe): manda a
    // escrita (60) e o teclado toca 63.
    expect(
      const PitchFrame(k, keyboardShiftsIn: true).outFromWritten(written),
      written,
    );
  });
}

void _parte2() {
  test('a saída e a entrada do teclado são independentes', () {
    const frame = PitchFrame(
      k,
      keyboardShiftsOut: true,
      keyboardShiftsIn: false,
    );
    expect(frame.writtenFromReceived(63), written);
    expect(frame.outFromWritten(written), sounding);
    const outro = PitchFrame(
      k,
      keyboardShiftsOut: false,
      keyboardShiftsIn: true,
    );
    expect(outro.writtenFromReceived(60), written);
    expect(outro.outFromWritten(written), written);
  });
}

void _parte3() {
  test('o monitor é a soada da escrita da recebida', () {
    for (var k = -12; k <= 12; k++) {
      for (final out in [false, true]) {
        final frame = PitchFrame(k, keyboardShiftsOut: out);
        for (var r = 21; r <= 108; r++) {
          expect(
            frame.monitorFromReceived(r),
            frame.soundingFromWritten(frame.writtenFromReceived(r)),
          );
        }
      }
    }
  });
}

void _parte4() {
  test('o teclado em TRANSPOSE = −k, de ponta a ponta, em toda tabela', () {
    // Cada linha da tabela do Q00: apertar a tecla escrita com o teclado
    // no `keyboard` certo faz o ouvido ouvir o tom original, nos quatro
    // jeitos de teclado.
    for (var fifths = -7; fifths <= 7; fifths++) {
      final t = Transposition.toNoAccidentals(
        fifths,
        range: (lowest: 40, highest: 90),
      );
      if (t == null) continue;
      _tecladoDaLinha(t);
    }
  });
}

/// Os quatro jeitos de teclado de uma linha da tabela: com o `keyboard` de
/// [t], a tecla escrita faz o ouvido ouvir o tom original.
void _tecladoDaLinha(Transposition t) {
  for (final out in [false, true]) {
    for (final inn in [false, true]) {
      final frame = PitchFrame(
        t.semitones,
        keyboardShiftsOut: out,
        keyboardShiftsIn: inn,
      );
      for (var w = 40; w <= 90; w++) {
        // A tecla w, com o TRANSPOSE em t.keyboard, soa w + keyboard.
        final heard = w + t.keyboard;
        expect(frame.soundingFromWritten(w), heard);
        // O que o teclado manda: a soada (transpõe a saída) ou a escrita.
        final received = out ? heard : w;
        expect(frame.writtenFromReceived(received), w);
        expect(frame.monitorFromReceived(received), heard);
        // O que o app manda: o teclado soa `heard` nos dois casos.
        final sent = frame.outFromWritten(w);
        expect(inn ? sent + t.keyboard : sent, heard);
      }
    }
  }
}

// Testes: a tabela de verdade (k = −3, tecla Dó) · quando o som é do app
void _parte5() {
  group('a tabela de verdade (k = −3, tecla Dó)', () {
    _parte1();
    _parte2();
  });
  group('quando o som é do app', () {
    test('o teclado não transpõe nada, seja qual for a marca guardada', () {
      for (final out in [false, true]) {
        for (final inn in [false, true]) {
          final frame = PitchFrame(
            k,
            keyboardShiftsOut: out,
            keyboardShiftsIn: inn,
            appIsSound: true,
          );
          // A pessoa deixou o TRANSPOSE em 0: a recebida é a escrita.
          expect(frame.writtenFromReceived(60), written);
          // O app toca a soada, no monitor e no motor.
          expect(frame.monitorFromReceived(60), sounding);
          expect(frame.soundingFromWritten(written), sounding);
          expect(frame.outFromWritten(written), sounding);
        }
      }
    });
  });
}

// Testes: sem transposição · para qualquer k
void _parte6() {
  group('sem transposição', () {
    test('identity é o caminho de hoje: tudo devolve o mesmo número', () {
      expect(PitchFrame.identity.isIdentity, isTrue);
      for (var p = 21; p <= 108; p++) {
        expect(PitchFrame.identity.writtenFromReceived(p), p);
        expect(PitchFrame.identity.soundingFromWritten(p), p);
        expect(PitchFrame.identity.monitorFromReceived(p), p);
        expect(PitchFrame.identity.outFromWritten(p), p);
      }
    });

    test('k = 0 ignora as marcas do teclado', () {
      for (final out in [false, true]) {
        for (final inn in [false, true]) {
          _zeroIgnoraTeclado(out, inn);
        }
      }
    });
  });
  group('para qualquer k', () {
    _parte3();
    _parte4();
  });
}

void _parte7() {
  test(
    'para o motor: o teclado MIDI lê pela regra dele, o app toca a soada',
    () {
      const plain = PitchFrame(-3);
      const shiftsIn = PitchFrame(-3, keyboardShiftsIn: true);
      expect(plain.engineFromWritten(60, midiKeyboard: false), 63);
      expect(shiftsIn.engineFromWritten(60, midiKeyboard: false), 63);
      expect(plain.engineFromWritten(60, midiKeyboard: true), 63);
      expect(shiftsIn.engineFromWritten(60, midiKeyboard: true), 60);
      // Da tecla apertada ao motor: o monitor soma a conversão da entrada.
      const shiftsOut = PitchFrame(-3, keyboardShiftsOut: true);
      expect(shiftsOut.engineFromReceived(63, midiKeyboard: false), 63);
      expect(plain.engineFromReceived(60, midiKeyboard: false), 63);
      expect(
        PitchFrame.identity.engineFromReceived(60, midiKeyboard: true),
        60,
      );
    },
  );
  test('igualdade e texto', () {
    expect(const PitchFrame(-3), const PitchFrame(-3));
    expect(const PitchFrame(-3), isNot(const PitchFrame(-3, appIsSound: true)));
    expect(
      const PitchFrame(-3, keyboardShiftsIn: true).hashCode,
      const PitchFrame(-3, keyboardShiftsIn: true).hashCode,
    );
    expect(const PitchFrame(-3).toString(), contains('k=-3'));
  });
}

// EX01, critério 1 — `ChordSymbol`: a leitura da cifra (as linhas da tabela
// do EX00), a escrita nas duas grafias, os erros, as classes de altura e os
// graus.

import 'package:test/test.dart';
import 'package:zywny_music/chord.dart';

ChordSymbol _chord(String text) {
  final chord = ChordSymbol.parse(text);
  expect(chord, isNotNull, reason: '`$text` deveria ser lida');
  return chord!;
}

/// As cifras que a escrita tem de devolver iguais nas duas grafias.
const _cifras = [
  'C',
  'Cm',
  'Cdim',
  'Caug',
  'C7',
  'Cmaj7',
  'Cm7',
  'Cm7b5',
  'Cdim7',
  'C6',
  'Cm6',
  'C6/9',
  'C9',
  'Cm9',
  'Cmaj9',
  'C11',
  'C13',
  'C7b9',
  'C7#9',
  'C7#11',
  'C7b13',
  'C7alt',
  'C7sus4',
  'Csus2',
  'Csus4',
  'C5',
  'CmMaj7',
  'Cadd9',
  'C/E',
  'F#m7',
  'Bbm7b5',
  'Eb7',
  'Ab7#11',
  'Bb7',
  'Dbmaj7',
  'G#dim7',
  'F7b5',
  'Cm7/Bb',
  'Db9#11',
  'Gm6',
  'E7#5',
  'Bm7b9',
  'Abmaj7/G',
  'A7sus4',
  'D7b9#9',
];

void main() {
  group('leitura', () {
    final tabela = {
      'C': {0, 4, 7},
      'Cm': {0, 3, 7},
      'Cdim': {0, 3, 6},
      'Caug': {0, 4, 8},
      'C7': {0, 4, 7, 10},
      'Cmaj7': {0, 4, 7, 11},
      'Cm7': {0, 3, 7, 10},
      'Cm7b5': {0, 3, 6, 10},
      'Cdim7': {0, 3, 6, 9},
      'C6': {0, 4, 7, 9},
      'C9': {0, 2, 4, 7, 10},
      'C7b9': {0, 1, 4, 7, 10},
      'Csus4': {0, 5, 7},
      'Cm7(b5)': {0, 3, 6, 10},
      'C°': {0, 3, 6},
      'C°7': {0, 3, 6, 9},
      'C+': {0, 4, 8},
      'C7(4)': {0, 5, 7, 10},
      'C5': {0, 7},
      'C6/9': {0, 2, 4, 7, 9},
      'C7alt': {0, 1, 3, 4, 6, 8, 10},
      'F/G': {0, 5, 7, 9},
    };
    tabela.forEach((texto, pitches) {
      test('`$texto` tem as classes $pitches', () {
        expect(_chord(texto).pitchClasses, pitches);
      });
    });

    test('C7M é Cmaj7 (as duas grafias são a mesma cifra)', () {
      expect(_chord('C7M'), _chord('Cmaj7'));
    });

    test('`F/G` tem o baixo no G', () {
      final chord = _chord('F/G');
      expect(chord.bass, 7);
      expect(chord.bassSpelling, 'G');
      expect(chord.pitchClasses, contains(7));
    });

    test('a grafia da fundamental segue a cifra: Bb7(#11), F#m7, Eb', () {
      expect(_chord('Bb7(#11)').rootSpelling, 'Bb');
      expect(_chord('Bb7(#11)').root, 10);
      expect(_chord('F#m7').rootSpelling, 'F#');
      expect(_chord('F#m7').root, 6);
      expect(_chord('Eb').root, 3);
    });

    test('♯ e ♭ valem como # e b', () {
      expect(_chord('B♭7'), _chord('Bb7'));
      expect(_chord('F♯m'), _chord('F#m'));
    });
  });

  group('erros', () {
    String? erro(String texto) {
      String? mensagem;
      final chord = ChordSymbol.parse(texto, error: (m) => mensagem = m);
      expect(chord, isNull, reason: '`$texto` não deveria ser lida');
      return mensagem;
    }

    test('sobra que não entendeu: `Cxyz`', () {
      expect(erro('Cxyz'), '`Cxyz`: não entendi `xyz`.');
    });

    test('fundamental inválida: `H7`', () {
      expect(erro('H7'), contains('fundamental'));
    });

    test('texto vazio', () {
      expect(erro(''), contains('vazia'));
    });
  });

  group('escrita', () {
    test('as duas grafias da tabela do EX01', () {
      expect(_chord('Cm7b5').label(ChordNotation.american), 'Cm7b5');
      expect(_chord('Cm7b5').label(ChordNotation.brazilian), 'Cm7(b5)');
      expect(_chord('Cmaj7').label(ChordNotation.brazilian), 'C7M');
      expect(_chord('Cdim7').label(ChordNotation.brazilian), 'C°7');
      expect(_chord('Csus4').label(ChordNotation.brazilian), 'C4');
      expect(_chord('C7b9').label(ChordNotation.brazilian), 'C7(b9)');
      expect(_chord('C7(b9)').label(ChordNotation.american), 'C7b9');
      expect(_chord('F/G').label(ChordNotation.american), 'F/G');
    });

    test('a escrita devolve a cifra lida, nas duas grafias (40 e mais)', () {
      expect(_cifras.length, greaterThanOrEqualTo(40));
      for (final texto in _cifras) {
        final chord = _chord(texto);
        for (final notation in ChordNotation.values) {
          final escrita = chord.label(notation);
          expect(
            ChordSymbol.parse(escrita),
            chord,
            reason: '`$texto` escrita como `$escrita` (${notation.name})',
          );
        }
      }
    });

    test('diminuto: C° é a tríade, e C°7 a sétima (kDegreeSignMeansDim7)', () {
      expect(kDegreeSignMeansDim7, isFalse);
      expect(_chord('C°').quality, ChordQuality.diminished);
      expect(_chord('C°7').quality, ChordQuality.diminished7);
    });
  });

  group('classes de altura exigidas', () {
    test('C7: a 5ª justa pode faltar (omit5 por padrão)', () {
      final chord = _chord('C7');
      expect(chord.requiredPitchClasses(), {0, 4, 10});
      expect(chord.requiredPitchClasses(omit5: false), {0, 4, 7, 10});
      expect(chord.allowedPitchClasses(), {7});
    });

    test('a tríade exige as três notas e não tem nota opcional', () {
      final chord = _chord('C');
      expect(chord.requiredPitchClasses(), {0, 4, 7});
      expect(chord.allowedPitchClasses(), isEmpty);
    });
  });

  group('graus', () {
    test('degreeOf diz o nome da classe no acorde', () {
      expect(_chord('C7').degreeOf(4), '3');
      expect(_chord('C7').degreeOf(10), 'b7');
      expect(_chord('Cm').degreeOf(3), 'b3');
      expect(_chord('C7b9').degreeOf(1), 'b9');
      expect(_chord('Cm7b5').degreeOf(6), 'b5');
      expect(_chord('C7#11').degreeOf(6), '#11');
      expect(_chord('Cdim7').degreeOf(9), 'bb7');
    });
  });
}

// EX06 — `scaleFingering` e `arpeggioFingering`: o dedilhado que o livro traz
// (Pike), e `null` onde ele não traz.

import 'package:test/test.dart';
import 'package:zywny_music/chord_degree.dart';
import 'package:zywny_music/fingering.dart';
import 'package:zywny_music/scale.dart';

KeySpec _key(String texto) {
  final key = KeySpec.parse(texto);
  expect(key, isNotNull, reason: 'o tom `$texto`');
  return key!;
}

void main() {
  group('escala maior, mão direita (Pike, exemplo 121)', () {
    test('dó maior, uma oitava: 1 2 3 1 2 3 4 5', () {
      expect(
        scaleFingering(ScaleKind.major, _key('C'), right: true, octaves: 1),
        [1, 2, 3, 1, 2, 3, 4, 5],
      );
    });

    test('duas oitavas: a primeira, e depois 7 notas por oitava', () {
      expect(
        scaleFingering(ScaleKind.major, _key('C'), right: true, octaves: 2),
        [1, 2, 3, 1, 2, 3, 4, 5, 1, 2, 3, 1, 2, 3, 4],
      );
    });

    test('a família vale para sol, ré, lá, mi e si', () {
      for (final tom in ['G', 'D', 'A', 'E', 'B']) {
        expect(
          scaleFingering(ScaleKind.major, _key(tom), right: true, octaves: 1),
          [1, 2, 3, 1, 2, 3, 4, 5],
          reason: 'maior de $tom',
        );
      }
    });

    test('tônica fora da família não tem dedilhado (null)', () {
      for (final tom in ['F', 'Bb', 'Eb', 'Ab', 'Db', 'F#']) {
        expect(
          scaleFingering(ScaleKind.major, _key(tom), right: true, octaves: 1),
          isNull,
          reason: 'maior de $tom',
        );
      }
    });
  });

  group('escala maior, mão esquerda (Pike, exemplo 121)', () {
    test('dó maior, uma oitava: 5 4 3 2 1 3 2 1', () {
      expect(
        scaleFingering(ScaleKind.major, _key('C'), right: false, octaves: 1),
        [5, 4, 3, 2, 1, 3, 2, 1],
      );
    });

    test('a esquerda tem só uma oitava: duas são null', () {
      expect(
        scaleFingering(ScaleKind.major, _key('C'), right: false, octaves: 2),
        isNull,
      );
    });
  });

  group('escala menor harmônica (Pike, exemplos 124 e 125)', () {
    test('lá menor harmônica, mão direita: 1 2 3 1 2 3 4 5', () {
      expect(
        scaleFingering(
          ScaleKind.harmonicMinor,
          _key('Am'),
          right: true,
          octaves: 1,
        ),
        [1, 2, 3, 1, 2, 3, 4, 5],
      );
    });

    test('lá menor harmônica, mão esquerda: 5 4 3 2 1 3 2 1', () {
      expect(
        scaleFingering(
          ScaleKind.harmonicMinor,
          _key('Am'),
          right: false,
          octaves: 1,
        ),
        [5, 4, 3, 2, 1, 3, 2, 1],
      );
    });

    test('ré menor harmônica tem a mesma tabela', () {
      expect(
        scaleFingering(
          ScaleKind.harmonicMinor,
          _key('Dm'),
          right: true,
          octaves: 1,
        ),
        [1, 2, 3, 1, 2, 3, 4, 5],
      );
    });

    test('a família é só lá e ré: as outras são null', () {
      expect(
        scaleFingering(
          ScaleKind.harmonicMinor,
          _key('Em'),
          right: true,
          octaves: 1,
        ),
        isNull,
      );
    });

    test('a escala natural e as outras não têm dedilhado', () {
      expect(
        scaleFingering(
          ScaleKind.naturalMinor,
          _key('Am'),
          right: true,
          octaves: 1,
        ),
        isNull,
      );
      expect(
        scaleFingering(ScaleKind.blues, _key('C'), right: true, octaves: 1),
        isNull,
      );
    });
  });

  group('arpejo de tríade (Pike, exemplo 126)', () {
    test('dó maior, mão direita: 1 2 3 5 numa oitava', () {
      expect(arpeggioFingering(_key('C'), right: true, octaves: 1), [
        1,
        2,
        3,
        5,
      ]);
    });

    test('duas oitavas: 1 2 3 1 2 3 5, como no exemplo do livro', () {
      expect(arpeggioFingering(_key('C'), right: true, octaves: 2), [
        1,
        2,
        3,
        1,
        2,
        3,
        5,
      ]);
    });

    test('mão esquerda: 5 3 2 1 numa oitava', () {
      expect(arpeggioFingering(_key('C'), right: false, octaves: 1), [
        5,
        3,
        2,
        1,
      ]);
    });

    test('tônica fora da família não tem dedilhado', () {
      expect(arpeggioFingering(_key('Bb'), right: true, octaves: 1), isNull);
    });
  });
}

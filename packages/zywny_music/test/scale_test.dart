// EX06 — `scaleDegrees`: as notas de cada escala com a grafia do tom.

import 'package:test/test.dart';
import 'package:zywny_music/chord_degree.dart';
import 'package:zywny_music/scale.dart';

KeySpec _key(String texto) {
  final key = KeySpec.parse(texto);
  expect(key, isNotNull, reason: 'o tom `$texto`');
  return key!;
}

/// As notas da escala [kind] no tom [tom], escritas como `F#`, `Bb`, `Eb`.
List<String> _names(ScaleKind kind, String tom) => [
  for (final t in scaleDegrees(kind, _key(tom))) t.toString(),
];

void main() {
  group('grafia, para C, F# e Bb (a tabela escrita à mão)', () {
    test('dó maior não tem acidente', () {
      expect(_names(ScaleKind.major, 'C'), ['C', 'D', 'E', 'F', 'G', 'A', 'B']);
    });

    test('fá sustenido maior tem os sete sustenidos da armadura', () {
      expect(_names(ScaleKind.major, 'F#'), [
        'F#',
        'G#',
        'A#',
        'B',
        'C#',
        'D#',
        'E#',
      ]);
    });

    test('si bemol maior: si e mi com bemol', () {
      expect(_names(ScaleKind.major, 'Bb'), [
        'Bb',
        'C',
        'D',
        'Eb',
        'F',
        'G',
        'A',
      ]);
    });

    test('lá menor harmônica sobe o sol para sustenido', () {
      expect(_names(ScaleKind.harmonicMinor, 'Am'), [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G#',
      ]);
    });

    test('ré bemol maior escreve os bemóis (não dó sustenido)', () {
      expect(_names(ScaleKind.major, 'Db'), [
        'Db',
        'Eb',
        'F',
        'Gb',
        'Ab',
        'Bb',
        'C',
      ]);
    });
  });

  group('as 12 tonalidades', () {
    test('a maior tem as classes de altura da tônica mais o intervalo', () {
      for (final tom in [
        'C',
        'Db',
        'D',
        'Eb',
        'E',
        'F',
        'F#',
        'G',
        'Ab',
        'A',
        'Bb',
        'B',
      ]) {
        final key = _key(tom);
        final tones = scaleDegrees(ScaleKind.major, key);
        expect(
          [for (final t in tones) t.pitchClass],
          [
            for (final i in [0, 2, 4, 5, 7, 9, 11]) (key.tonic + i) % 12,
          ],
          reason: 'a maior de $tom',
        );
      }
    });

    test('cada letra aparece uma vez na maior (sete letras, sete notas)', () {
      for (final tom in [
        'C',
        'Db',
        'D',
        'Eb',
        'E',
        'F',
        'F#',
        'G',
        'Ab',
        'A',
        'Bb',
        'B',
      ]) {
        final letters = [
          for (final t in scaleDegrees(ScaleKind.major, _key(tom))) t.step,
        ];
        expect(letters.toSet().length, 7, reason: 'a maior de $tom');
      }
    });

    test('a alteração fica entre −2 e +2 em todas as escalas', () {
      for (final kind in ScaleKind.values) {
        for (final tom in ['C', 'F#', 'Bb', 'Db', 'G#', 'Eb']) {
          for (final t in scaleDegrees(kind, _key(tom))) {
            expect(
              t.alter,
              inInclusiveRange(-2, 2),
              reason: '${kind.wire} em $tom: $t',
            );
          }
        }
      }
    });
  });

  group('outras escalas, em dó', () {
    test('pentatônica maior e menor', () {
      expect(_names(ScaleKind.majorPentatonic, 'C'), ['C', 'D', 'E', 'G', 'A']);
      expect(_names(ScaleKind.minorPentatonic, 'C'), [
        'C',
        'Eb',
        'F',
        'G',
        'Bb',
      ]);
    });

    test('blues tem a quinta diminuta com a letra de sol', () {
      expect(_names(ScaleKind.blues, 'C'), ['C', 'Eb', 'F', 'Gb', 'G', 'Bb']);
    });

    test('tons inteiros sobem com sustenidos', () {
      expect(_names(ScaleKind.wholeTone, 'C'), [
        'C',
        'D',
        'E',
        'F#',
        'G#',
        'A#',
      ]);
    });

    test('bebop dominante tem a sétima maior de passagem', () {
      expect(_names(ScaleKind.bebopDominant, 'C'), [
        'C',
        'D',
        'E',
        'F',
        'G',
        'A',
        'Bb',
        'B',
      ]);
    });

    test('meio-tom e tom (diminuta) e a alterada', () {
      expect(_names(ScaleKind.diminishedHw, 'C'), [
        'C',
        'Db',
        'Eb',
        'E',
        'F#',
        'G',
        'A',
        'Bb',
      ]);
      expect(_names(ScaleKind.altered, 'C'), [
        'C',
        'Db',
        'Eb',
        'Fb',
        'Gb',
        'Ab',
        'Bb',
      ]);
    });

    test('os modos saem da armadura da maior com a letra do modo', () {
      expect(_names(ScaleKind.dorian, 'D'), [
        'D',
        'E',
        'F',
        'G',
        'A',
        'B',
        'C',
      ]);
      expect(_names(ScaleKind.mixolydian, 'G'), [
        'G',
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
      ]);
    });
  });
}

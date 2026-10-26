// EX01, critério 4 — `rootSequence`: os ciclos na ordem da tabela do EX00,
// a volta a 12 e o sorteio sem repetir em seguida.

import 'dart:math' show Random;

import 'package:test/test.dart';
import 'package:zywny_music/chord_degree.dart';
import 'package:zywny_music/chord_sequence.dart';

void main() {
  test('cycle5 a partir de C: C F B♭ E♭ A♭ D♭ G♭ B E A D G', () {
    expect(rootSequence(RootSequence.cycle5, count: 12), [
      0,
      5,
      10,
      3,
      8,
      1,
      6,
      11,
      4,
      9,
      2,
      7,
    ]);
  });

  test('cycle5 cobre as 12 fundamentais, todas diferentes', () {
    final seq = rootSequence(RootSequence.cycle5, count: 12);
    expect(seq.toSet(), hasLength(12));
  });

  test('cycle4 a partir de C: C G D A E B F♯ D♭ A♭ E♭ B♭ F', () {
    expect(rootSequence(RootSequence.cycle4, count: 12), [
      0,
      7,
      2,
      9,
      4,
      11,
      6,
      1,
      8,
      3,
      10,
      5,
    ]);
  });

  test('chromatic desce por semitom', () {
    expect(rootSequence(RootSequence.chromatic, count: 4), [0, 11, 10, 9]);
  });

  test(
    'wholeTone cobre as 12, pela série de tons e a série um semitom acima',
    () {
      final seq = rootSequence(RootSequence.wholeTone, count: 12);
      expect(seq, [0, 10, 8, 6, 4, 2, 1, 11, 9, 7, 5, 3]);
      expect(seq.toSet(), hasLength(12));
    },
  );

  test('from desloca o ciclo', () {
    expect(rootSequence(RootSequence.cycle5, from: 2, count: 3), [2, 7, 0]);
  });

  test(
    'random sorteia sem repetir em seguida (1000 sorteios, semente fixa)',
    () {
      final seq = rootSequence(
        RootSequence.random,
        count: 1000,
        rng: Random(42),
      );
      expect(seq, hasLength(1000));
      expect(seq.first, 0);
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], isNot(seq[i - 1]), reason: 'posição $i');
      }
      expect(seq.every((p) => p >= 0 && p < 12), isTrue);
    },
  );

  test('diatonic sobe e desce os sete graus do tom', () {
    final key = KeySpec.parse('C')!;
    expect(rootSequence(RootSequence.diatonic, count: 12, key: key), [
      0,
      2,
      4,
      5,
      7,
      9,
      11,
      9,
      7,
      5,
      4,
      2,
    ]);
  });

  test('diatonic sem tom é um erro', () {
    expect(
      () => rootSequence(RootSequence.diatonic, count: 3),
      throwsArgumentError,
    );
  });
}

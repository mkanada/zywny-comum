// EX01, critério 3 — `buildVoicing`, `readVoicing`, a condução de vozes e o
// limite de 3ª grave: cada molde em 12 fundamentais, as inversões, o `near`.

import 'package:test/test.dart';
import 'package:zywny_music/chord.dart';
import 'package:zywny_music/chord_voicing.dart';

ChordSymbol _chord(String texto) {
  final chord = ChordSymbol.parse(texto);
  expect(chord, isNotNull, reason: '`$texto`');
  return chord!;
}

const _fundamentais = [
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
];

const _setimas = ['7', 'm7', 'maj7', 'm7b5', 'dim7'];

void main() {
  group('cada molde, em 12 fundamentais e 5 qualidades de sétima', () {
    for (final shape in VoicingShape.values) {
      test(
        '$shape: as notas cabem na faixa e readVoicing reconhece o molde',
        () {
          for (final raiz in _fundamentais) {
            for (final qualidade in _setimas) {
              final chord = _chord('$raiz$qualidade');
              final pitches = buildVoicing(
                chord,
                shape: shape,
                inversion: Inversion.any,
                lowest: 48,
                highest: 84,
              );
              expect(
                pitches.every((p) => p >= 48 && p <= 84),
                isTrue,
                reason: '$raiz$qualidade $shape: $pitches',
              );
              final reading = readVoicing(pitches, chord);
              expect(
                reading.shapes,
                contains(shape),
                reason: '$raiz$qualidade $shape: $pitches',
              );
            }
          }
        },
      );
    }
  });

  group('inversão pelo baixo', () {
    test('C7 com a 3ª embaixo: a nota mais grave é o E', () {
      final pitches = buildVoicing(
        _chord('C7'),
        inversion: Inversion.first,
        lowest: 48,
        highest: 84,
      );
      expect(pitches.first % 12, 4);
      expect(readVoicing(pitches, _chord('C7')).inversion, Inversion.first);
    });

    test('C7 com a 5ª, a 7ª e a fundamental embaixo', () {
      for (final (inversion, pc) in [
        (Inversion.second, 7),
        (Inversion.third, 10),
        (Inversion.root, 0),
      ]) {
        final pitches = buildVoicing(
          _chord('C7'),
          inversion: inversion,
          lowest: 48,
          highest: 84,
        );
        expect(pitches.first % 12, pc, reason: '$inversion: $pitches');
      }
    });

    test('um baixo de barra manda sobre a inversão (F/G tem G embaixo)', () {
      final pitches = buildVoicing(
        _chord('F/G'),
        inversion: Inversion.root,
        lowest: 48,
        highest: 84,
      );
      expect(pitches.first % 12, 7);
    });
  });

  group('moldes que põem outra nota embaixo', () {
    test('upperTriad: a 7ª fica embaixo, com a tríade em cima', () {
      final pitches = buildVoicing(
        _chord('C7'),
        shape: VoicingShape.upperTriad,
        lowest: 48,
        highest: 84,
      );
      expect(pitches.first % 12, 10, reason: '$pitches');
      expect(pitches.skip(1).map((p) => p % 12).toSet(), {0, 4, 7});
    });

    test('drop2: a 5ª desce uma oitava (G7 vira D G B F)', () {
      final pitches = buildVoicing(
        _chord('G7'),
        shape: VoicingShape.drop2,
        lowest: 48,
        highest: 72,
      );
      expect(pitches.first % 12, 2, reason: '$pitches');
      expect(pitches.map((p) => p % 12).toSet(), {2, 7, 11, 5});
    });
  });

  group('condução de vozes', () {
    test('voiceLeadingDistance: C → F na 2ª inversão custa 3', () {
      expect(voiceLeadingDistance([60, 64, 67], [60, 65, 69]), 3);
      expect(voiceLeadingDistance([60, 64, 67], [60, 64, 67]), 0);
    });

    test('voice a mais ou a menos custa até a nota mais perto', () {
      expect(voiceLeadingDistance([60, 64, 67, 70], [60, 64, 67]), 3);
    });

    test('com near, C → F escolhe a 2ª inversão de F', () {
      final pitches = buildVoicing(
        _chord('F'),
        inversion: Inversion.any,
        lowest: 48,
        highest: 72,
        near: [60, 64, 67],
      );
      expect(pitches, [60, 65, 69]);
    });
  });

  group('leitura de um voicing tocado', () {
    test('C7 em posição fechada: o molde close, a fundamental embaixo', () {
      final reading = readVoicing([60, 64, 67, 70], _chord('C7'));
      expect(reading.shapes, contains(VoicingShape.close));
      expect(reading.inversion, Inversion.root);
      expect(reading.centre, 65);
    });

    test('guide tones (3ª e 7ª) são o molde sevenThree', () {
      final reading = readVoicing([64, 70], _chord('C7'));
      expect(reading.shapes, contains(VoicingShape.sevenThree));
    });
  });

  group('limite da 3ª grave (Dó3)', () {
    test('uma 3ª começando abaixo do Dó3 embola', () {
      expect(hasMuddyLowThird([40, 44, 60]), isTrue);
    });

    test('a 3ª a partir do Dó3 não embola', () {
      expect(hasMuddyLowThird([48, 52, 60]), isFalse);
    });
  });

  group('o molde tenth cai para a fundamental e a 7ª', () {
    test('sem lugar para a 10ª, C7 fica com a 7ª', () {
      final pitches = buildVoicing(
        _chord('C7'),
        shape: VoicingShape.tenth,
        lowest: 48,
        highest: 58,
      );
      expect(pitches, [48, 58]);
    });
  });

  test('um molde que o acorde não tem é recusado', () {
    expect(
      () => buildVoicing(
        _chord('C'),
        shape: VoicingShape.shell17,
        lowest: 48,
        highest: 84,
      ),
      throwsArgumentError,
    );
  });
}

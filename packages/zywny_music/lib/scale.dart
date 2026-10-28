import 'package:meta/meta.dart';

import 'chord_degree.dart';

// EX06 — as escalas do `play-pattern`: os intervalos de cada uma e a grafia
// das notas (letra e alteração) pelo tom. Dart puro.

const _naturalPitchClass = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};
const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

/// Uma nota da escala com a grafia do tom: a letra (`C`…`B`), a alteração
/// (−2 a +2) e a classe de altura (dó = 0).
@immutable
class ScaleTone {
  const ScaleTone({
    required this.step,
    required this.alter,
    required this.pitchClass,
  });

  final String step;
  final int alter;
  final int pitchClass;

  @override
  bool operator ==(Object other) =>
      other is ScaleTone &&
      other.step == step &&
      other.alter == alter &&
      other.pitchClass == pitchClass;

  @override
  int get hashCode => Object.hash(step, alter, pitchClass);

  @override
  String toString() => '$step${alter > 0 ? '#' * alter : 'b' * -alter}';
}

/// As escalas do `scale:` do `play-pattern`. Cada uma é uma lista de passos:
/// a letra (deslocamento a partir da tônica, de 0 a 6) e o semitom a partir
/// da tônica. A letra decide a grafia (Dó♭ e Si♭ são letras diferentes do
/// mesmo tom).
enum ScaleKind {
  major('major', [(0, 0), (1, 2), (2, 4), (3, 5), (4, 7), (5, 9), (6, 11)]),
  naturalMinor('natural-minor', [
    (0, 0),
    (1, 2),
    (2, 3),
    (3, 5),
    (4, 7),
    (5, 8),
    (6, 10),
  ]),
  harmonicMinor('harmonic-minor', [
    (0, 0),
    (1, 2),
    (2, 3),
    (3, 5),
    (4, 7),
    (5, 8),
    (6, 11),
  ]),
  melodicMinor('melodic-minor', [
    (0, 0),
    (1, 2),
    (2, 3),
    (3, 5),
    (4, 7),
    (5, 9),
    (6, 11),
  ]),
  blues('blues', [(0, 0), (2, 3), (3, 5), (4, 6), (4, 7), (6, 10)]),
  majorPentatonic('major-pentatonic', [(0, 0), (1, 2), (2, 4), (4, 7), (5, 9)]),
  minorPentatonic('minor-pentatonic', [
    (0, 0),
    (2, 3),
    (3, 5),
    (4, 7),
    (6, 10),
  ]),
  dorian('dorian', [(0, 0), (1, 2), (2, 3), (3, 5), (4, 7), (5, 9), (6, 10)]),
  phrygian('phrygian', [
    (0, 0),
    (1, 1),
    (2, 3),
    (3, 5),
    (4, 7),
    (5, 8),
    (6, 10),
  ]),
  lydian('lydian', [(0, 0), (1, 2), (2, 4), (3, 6), (4, 7), (5, 9), (6, 11)]),
  mixolydian('mixolydian', [
    (0, 0),
    (1, 2),
    (2, 4),
    (3, 5),
    (4, 7),
    (5, 9),
    (6, 10),
  ]),
  locrian('locrian', [(0, 0), (1, 1), (2, 3), (3, 5), (4, 6), (5, 8), (6, 10)]),
  wholeTone('whole-tone', [(0, 0), (1, 2), (2, 4), (3, 6), (4, 8), (5, 10)]),
  diminishedHw('diminished-hw', [
    (0, 0),
    (1, 1),
    (2, 3),
    (2, 4),
    (3, 6),
    (4, 7),
    (5, 9),
    (6, 10),
  ]),
  diminishedWh('diminished-wh', [
    (0, 0),
    (1, 2),
    (2, 3),
    (3, 5),
    (4, 6),
    (5, 8),
    (5, 9),
    (6, 11),
  ]),
  bebopDominant('bebop-dominant', [
    (0, 0),
    (1, 2),
    (2, 4),
    (3, 5),
    (4, 7),
    (5, 9),
    (6, 10),
    (6, 11),
  ]),
  altered('altered', [(0, 0), (1, 1), (2, 3), (3, 4), (4, 6), (5, 8), (6, 10)]),
  lydianDominant('lydian-dominant', [
    (0, 0),
    (1, 2),
    (2, 4),
    (3, 6),
    (4, 7),
    (5, 9),
    (6, 10),
  ]);

  const ScaleKind(this.wire, this.steps);

  /// O nome no formato (`natural-minor`).
  final String wire;

  /// (letra, semitom) de cada nota de uma oitava, a partir da tônica.
  final List<(int, int)> steps;
}

/// As notas de uma oitava de [kind] no tom [key], a partir da tônica, com a
/// grafia pela letra. A cromática não está aqui: a grafia dela depende do
/// sentido (sobe com sustenidos, desce com bemóis), e quem a monta é o
/// `pattern_score.dart`.
List<ScaleTone> scaleDegrees(ScaleKind kind, KeySpec key) {
  final root = key.spelling[0];
  final rootLetter = _letters.indexOf(root);
  return [
    for (final (letter, semitones) in kind.steps)
      _spell(rootLetter, letter, (key.tonic + semitones) % 12),
  ];
}

/// A nota de letra `letras[(rootLetter + offset) % 7]` com a classe [pitchClass]:
/// a alteração é a distância dessa letra natural até a classe.
ScaleTone _spell(int rootLetter, int offset, int pitchClass) {
  final step = _letters[(rootLetter + offset) % 7];
  var alter = (pitchClass - _naturalPitchClass[step]!) % 12;
  if (alter > 6) alter -= 12;
  return ScaleTone(step: step, alter: alter, pitchClass: pitchClass);
}

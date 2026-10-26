import 'package:meta/meta.dart';

import 'chord_degree.dart';

/// Uma progressão da biblioteca: graus por compasso e de onde ela vem (livro
/// e capítulo, para os textos das lições).
@immutable
class Progression {
  const Progression({
    required this.name,
    required this.chart,
    required this.source,
  });

  final String name;

  /// Graus: `|` separa compassos, e um espaço separa acordes dentro do
  /// compasso.
  final String chart;
  final String source;

  /// Os compassos, cada um com a lista dos seus graus.
  List<List<String>> get bars => [
    for (final bar in chart.split('|')) bar.trim().split(RegExp(r'\s+')),
  ];

  int get barCount => bars.length;
}

/// Lê uma progressão escrita no próprio exercício (`progression:`), na mesma
/// sintaxe da biblioteca. Devolve `null` e chama [error] no primeiro grau que
/// não entende.
List<List<ChordDegree>>? parseProgression(
  String text, {
  void Function(String)? error,
}) {
  final bars = <List<ChordDegree>>[];
  for (final bar in text.split('|')) {
    final chords = <ChordDegree>[];
    for (final word in bar.trim().split(RegExp(r'\s+'))) {
      final degree = ChordDegree.parse(word, error: error);
      if (degree == null) return null;
      chords.add(degree);
    }
    bars.add(chords);
  }
  return bars;
}

/// A progressão com esse nome, ou `null`.
Progression? progressionNamed(String name) {
  for (final progression in kProgressions) {
    if (progression.name == name) return progression;
  }
  return null;
}

const _rhythmChangesA = Progression(
  name: 'rhythm-changes-a',
  chart:
      'Imaj7 vi7 | ii7 V7 | iii7 VI7 | ii7 V7 | Imaj7 I7 | IVmaj7 #iv°7 | '
      'Imaj7 V7 | Imaj7 Imaj7',
  source: 'Rawlins *Real Book* 3',
);

/// A biblioteca de progressões (EX01, seção 5).
final kProgressions = <Progression>[
  const Progression(
    name: 'I-IV-V-I',
    chart: 'I | IV | V | I',
    source: 'Pike 7; PFA 1',
  ),
  const Progression(
    name: 'I-V-vi-IV',
    chart: 'I | V | vi | IV',
    source: 'PFA 1',
  ),
  const Progression(
    name: 'I-vi-IV-V',
    chart: 'I | vi | IV | V',
    source: 'PFA 1 ("Blue Moon")',
  ),
  const Progression(
    name: 'vi-IV-I-V',
    chart: 'vi | IV | I | V',
    source: 'currículo 3.6',
  ),
  const Progression(
    name: 'ii-V-I',
    chart: 'ii7 | V7 | Imaj7 | Imaj7',
    source: 'Harrison *Intro* 2',
  ),
  const Progression(
    name: 'ii-V-i',
    chart: 'iiø7 | V7 | im7 | im7',
    source: 'Valerio *Latin* 2',
  ),
  const Progression(
    name: 'blues-12',
    chart: 'I7 | IV7 | I7 | I7 | IV7 | IV7 | I7 | I7 | V7 | IV7 | I7 | V7',
    source: 'Harrison *Blues* 3; PFA 2',
  ),
  const Progression(
    name: 'blues-12-quick',
    chart: 'I7 | IV7 | I7 | I7 | IV7 | IV7 | I7 | I7 | V7 | IV7 | I7 | V7',
    source: 'Harrison *Blues* 3 (com IV7 no compasso 2)',
  ),
  const Progression(
    name: 'minor-blues',
    chart: 'i7 | i7 | i7 | i7 | iv7 | iv7 | i7 | i7 | bVI7 | V7 | i7 | V7',
    source: 'PFA 10; Harrison *Jazz-Blues*',
  ),
  const Progression(
    name: 'jazz-blues',
    chart:
        'I7 | IV7 | I7 | v7 I7 | IV7 | #iv°7 | I7 | VI7 | ii7 | V7 | '
        'I7 VI7 | ii7 V7',
    source: 'PFA 7 e 10; Harrison *Jazz-Blues* 4',
  ),
  const Progression(
    name: 'circle-c',
    chart: 'I | IV | vii° | iii | vi | ii | V | I',
    source: 'PFA 1 ("Amazing Broken Chord Ballad")',
  ),
  const Progression(
    name: 'montuno-i-iv-v',
    chart: 'I IV | V IV',
    source: 'Martignon cap. 4',
  ),
  const Progression(
    name: 'turnaround',
    chart: 'I vi | ii V',
    source: 'PFA 3; Vinter; Rawlins cap. 4',
  ),
  const Progression(
    name: 'turnaround-sub',
    chart: 'iii7 bIII7 | ii7 bII7',
    source: 'Rawlins *Real Book* 4 (turnaround com subV)',
  ),
  _rhythmChangesA,
  const Progression(
    name: 'rhythm-changes-b',
    chart: 'III7 | III7 | VI7 | VI7 | II7 | II7 | V7 | V7',
    source: 'Rawlins *Real Book* 3 (ponte de Rhythm Changes)',
  ),
  Progression(
    name: 'long-rhythm-changes-a',
    chart: [
      for (final bar in _rhythmChangesA.bars)
        for (final chord in bar) chord,
    ].join(' | '),
    source: 'Rawlins *Real Book* 3',
  ),
  const Progression(
    name: 'honeysuckle-a',
    chart:
        'ii7 V7 | ii7 V7 | ii7 V7 | ii7 V7 | Imaj7 | Imaj7 | iiiø7 VI7 | '
        'ii7 V7',
    source: 'Rawlins *Real Book* 3 (*Honeysuckle Changes*)',
  ),
  const Progression(
    name: 'honeysuckle-b',
    chart: 'Imaj7 I7 | I7 | IVmaj7 | IVmaj7 | II7 | II7 | ii7 | V7',
    source: 'Rawlins *Real Book* 3 (ponte de *Honeysuckle*)',
  ),
  const Progression(
    name: 'doxy-a',
    chart:
        'Imaj7 VI7 | II7 V7 | Imaj7 VI7 | II7 V7 | Imaj7 I7 | IV7 #iv°7 | '
        'Imaj7 V7 | Imaj7 V7',
    source: 'Rawlins *Real Book* 3 (*Doxy Changes*)',
  ),
  const Progression(
    name: 'indiana-a',
    chart:
        'Imaj7 | VI7 | ii7 | ii7 | V7 | V7 | Imaj7 | ii7 V7 | Imaj7 | I7 | '
        'IVmaj7 | iv7 | Imaj7 | VI7 | ii7 V7 | Imaj7',
    source: 'Rawlins *Real Book* 3 (*Indiana / Donna Lee Changes*)',
  ),
  const Progression(
    name: 'rose-room-a',
    chart:
        'v7 I7 | IVmaj7 | iv7 bVII7 | Imaj7 | iiiø7 VI7 | ii7 | II7 | '
        'ii7 V7',
    source: 'Rawlins *Real Book* 3 (*Rose Room / In a Mellotone Changes*)',
  ),
  const Progression(
    name: 'pick-yourself-up-a',
    chart:
        'Imaj7 vi7 | ii7 V7 | iii7 vi7 | ii7 V7 | iii7 VI7 | ii7 V7 | '
        'iii7 VI7 | ii7 V7',
    source: 'Rawlins *Real Book* 3 (*Pick Yourself Up Changes*)',
  ),
  const Progression(
    name: 'miss-jones-b',
    chart:
        'bVImaj7 | iv7/bIII bVII7/bIII | bIIImaj7 | iv7/bVI bVII7/bVI | '
        'bVImaj7 | ii7/III V7/III | IIImaj7 | ii7 V7',
    source: 'Rawlins *Real Book* 3 (ponte de Coltrane / *Miss Jones*)',
  ),
];

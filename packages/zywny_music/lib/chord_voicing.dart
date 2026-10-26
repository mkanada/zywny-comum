import 'dart:math' show min;

import 'package:meta/meta.dart';

import 'chord.dart';

/// Nota mais grave em que uma 3ª pode começar sem embolar: Dó3 (Rawlins,
/// cap. 7). Ver [hasMuddyLowThird].
const kLowestThirdMidi = 48;

/// Os moldes de voicing (EX00, seção Voicing).
enum VoicingShape {
  close,
  shell17,
  shell13,
  sevenThree,
  sevenThreeExt,
  rootlessA,
  rootlessB,
  block,
  quartal,
  soWhat,
  tenth,
  upperTriad,
  twoHand5,
  drop2,
  splitExt,
}

/// Qual nota do acorde está embaixo. `any` = qualquer inversão vale.
enum Inversion { any, root, first, second, third }

/// O que [readVoicing] tirou de um conjunto de notas tocadas.
@immutable
class VoicingReading {
  const VoicingReading({
    required this.shapes,
    required this.inversion,
    required this.centre,
  });

  /// Os moldes que batem com as classes de altura. Vários, quando o mesmo
  /// conjunto serve a mais de um (o `close` e o `block` de quatro notas).
  final Set<VoicingShape> shapes;

  /// A nota mais grave pela fundamental, a 3ª, a 5ª ou a 7ª; `any` se não é
  /// nenhuma delas.
  final Inversion inversion;

  /// O centro da região, em MIDI (a média da mais grave e da mais aguda).
  final int centre;
}

/// Constrói alturas MIDI concretas para o acorde, de [lowest] a [highest].
///
/// O molde diz quais notas entram, e [inversion] qual fica embaixo. O
/// voicing que sobra é o de menor [voiceLeadingDistance] até [near] (o
/// voicing anterior); sem [near], o de centro mais perto do meio da faixa.
///
/// Num acorde com baixo (`F/G`), o baixo manda sobre a [inversion]. Nos
/// moldes que põem outra nota embaixo, `root` pede essa nota: no `upperTriad`,
/// a 7ª; no `drop2`, a 5ª, que desce uma oitava. Num molde sem a nota pedida,
/// fica a primeira nota do molde embaixo. O molde `tenth` cai para a
/// fundamental mais a 7ª se a 10ª não couber.
List<int> buildVoicing(
  ChordSymbol chord, {
  VoicingShape shape = VoicingShape.close,
  Inversion inversion = Inversion.root,
  required int lowest,
  required int highest,
  List<int>? near,
}) {
  final offsets = _shapeOffsets(chord, shape);
  if (offsets == null) {
    throw ArgumentError(
      '$shape não cabe em `${chord.label(ChordNotation.american)}`: o acorde '
      'não tem a nota que o molde pede.',
    );
  }
  final voicings = _placements(
    chord,
    offsets,
    shape: shape,
    inversion: inversion,
    lowest: lowest,
    highest: highest,
  );
  if (voicings.isEmpty) {
    if (shape == VoicingShape.tenth) {
      return buildVoicing(
        chord,
        shape: chord.seventh == null
            ? VoicingShape.close
            : VoicingShape.shell17,
        inversion: inversion,
        lowest: lowest,
        highest: highest,
        near: near,
      );
    }
    throw ArgumentError(
      '$shape de `${chord.label(ChordNotation.american)}` não cabe entre '
      '$lowest e $highest.',
    );
  }
  final middle = (lowest + highest) / 2;
  num score(List<int> voicing) => near == null
      ? ((voicing.first + voicing.last) / 2 - middle).abs()
      : voiceLeadingDistance(voicing, near);
  voicings.sort((a, b) => score(a).compareTo(score(b)));
  return voicings.first;
}

/// Soma dos menores deslocamentos (em semitons) emparelhando as vozes de [a]
/// e [b] em ordem de altura. Voz a mais ou a menos custa a distância até a
/// nota mais próxima do outro lado. É o "mínimo de movimento" do PFA 3.
int voiceLeadingDistance(List<int> a, List<int> b) {
  final x = [...a]..sort();
  final y = [...b]..sort();
  final paired = min(x.length, y.length);
  var total = 0;
  for (var i = 0; i < paired; i++) {
    total += (x[i] - y[i]).abs();
  }
  for (var i = paired; i < x.length; i++) {
    total += _nearest(x[i], y);
  }
  for (var i = paired; i < y.length; i++) {
    total += _nearest(y[i], x);
  }
  return total;
}

/// Lê um conjunto de notas tocadas: quais moldes batem, a inversão e o
/// centro da região. Não exige que o conjunto seja um voicing do app.
VoicingReading readVoicing(List<int> pitches, ChordSymbol chord) {
  final sorted = [...pitches]..sort();
  final played = {for (final p in sorted) p % 12};
  final shapes = <VoicingShape>{};
  for (final shape in VoicingShape.values) {
    final offsets = _shapeOffsets(chord, shape);
    if (offsets == null) continue;
    final expected = {for (final o in offsets) _mod12(chord.root + o)};
    final bass = chord.bass;
    if (bass != null) expected.add(bass);
    if (expected.length == played.length && expected.containsAll(played)) {
      shapes.add(shape);
    }
  }
  final lowestRel = _mod12(sorted.first % 12 - chord.root);
  final inversion = switch (lowestRel) {
    0 => Inversion.root,
    final r when r == chord.third => Inversion.first,
    final r when r == chord.fifth => Inversion.second,
    final r when r == chord.seventh => Inversion.third,
    _ => Inversion.any,
  };
  return VoicingReading(
    shapes: shapes,
    inversion: inversion,
    centre: (sorted.first + sorted.last) ~/ 2,
  );
}

/// Há uma 3ª (3 ou 4 semitons) começando abaixo de [kLowestThirdMidi]? Em
/// grave, ela embola no piano (Rawlins, cap. 7).
bool hasMuddyLowThird(List<int> pitches) {
  for (var i = 0; i < pitches.length; i++) {
    for (var j = i + 1; j < pitches.length; j++) {
      final gap = (pitches[i] - pitches[j]).abs();
      final low = min(pitches[i], pitches[j]);
      if ((gap == 3 || gap == 4) && low < kLowestThirdMidi) return true;
    }
  }
  return false;
}

int _mod12(int x) => ((x % 12) + 12) % 12;

int _nearest(int value, List<int> others) =>
    others.fold(1 << 30, (best, o) => min(best, (o - value).abs()));

/// Os intervalos do molde, em semitons a partir da fundamental (podem passar
/// de 11: a 9ª é 14). `null` quando o acorde não tem a nota que o molde pede.
List<int>? _shapeOffsets(ChordSymbol chord, VoicingShape shape) {
  final third = chord.third;
  final seventh = chord.seventh;
  final fifth = chord.fifth;
  return switch (shape) {
    VoicingShape.close => [...chord.intervals]..sort(),
    VoicingShape.shell17 => seventh == null ? null : [0, seventh],
    VoicingShape.shell13 => third == null ? null : [0, third],
    VoicingShape.sevenThree =>
      third == null || seventh == null ? null : [third, seventh],
    VoicingShape.sevenThreeExt =>
      third == null || seventh == null ? null : [third, seventh, 14],
    VoicingShape.rootlessA ||
    VoicingShape.rootlessB => _rootless(chord, shape == VoicingShape.rootlessA),
    VoicingShape.block =>
      third == null || seventh == null ? null : [0, third, fifth, seventh],
    VoicingShape.quartal => _quartal(chord.quality),
    VoicingShape.soWhat => [0, 5, 10, 15, 19],
    VoicingShape.tenth => third == null ? null : [0, third + 12],
    VoicingShape.upperTriad =>
      seventh == null
          ? null
          : [seventh, 12, 12 + _triadThird(chord.quality), 19],
    VoicingShape.twoHand5 =>
      third == null || seventh == null
          ? null
          : [0, seventh, third + 12, fifth + 12, 26],
    VoicingShape.drop2 =>
      third == null || seventh == null ? null : [fifth - 12, 0, third, seventh],
    VoicingShape.splitExt => _splitExt(chord),
  };
}

/// 3-5-7-9 (A) ou 7-9-3-5 (B), de baixo para cima. Na m7b5 falta a 9ª
/// (Rawlins, cap. 6); na dominante, a 13ª entra no lugar da 5ª; no acorde de
/// 6ª, a 6ª é a sétima do molde.
List<int>? _rootless(ChordSymbol chord, bool a) {
  final third = chord.third;
  final seventh = chord.seventh;
  if (third == null || seventh == null) return null;
  final fifth = chord.fifth;
  final quality = chord.quality;
  final halfDim = quality == ChordQuality.halfDiminished7;
  final dominant =
      quality == ChordQuality.dominant7 ||
      quality == ChordQuality.dominant7sus4;
  final sixth =
      quality == ChordQuality.major6 || quality == ChordQuality.minor6;
  if (a) {
    if (halfDim) return [third, fifth, seventh];
    if (dominant) return [third, 9, seventh, 14];
    if (sixth) return [third, fifth, 9, 14];
    return [third, fifth, seventh, 14];
  }
  if (halfDim) return [seventh, third + 12, fifth + 12];
  if (dominant) return [seventh, 14, third + 12, 21];
  if (sixth) return [9, 14, third + 12, fifth + 12];
  return [seventh, 14, third + 12, fifth + 12];
}

/// Quatro notas empilhadas em 4ª, pegando as notas da escala do acorde:
/// dórico para a menor com sétima, mixolídio para a dominante, lídio para a
/// maior com sétima, e maior para o resto. A 4ª é de grau em grau (de
/// 3 em 3 na escala), como a pauta a escreve.
List<int> _quartal(ChordQuality quality) {
  final scale = switch (quality) {
    ChordQuality.minor ||
    ChordQuality.minor7 ||
    ChordQuality.minor6 ||
    ChordQuality.halfDiminished7 => const [0, 2, 3, 5, 7, 9, 10],
    ChordQuality.dominant7 ||
    ChordQuality.dominant7sus4 => const [0, 2, 4, 5, 7, 9, 10],
    ChordQuality.major7 => const [0, 2, 4, 6, 7, 9, 11],
    _ => const [0, 2, 4, 5, 7, 9, 11],
  };
  return [for (var i = 0; i < 4; i++) _scaleStep(scale, 2 + 3 * i)];
}

int _scaleStep(List<int> scale, int degree) =>
    scale[degree % 7] + 12 * (degree ~/ 7);

/// A tríade de cima do [VoicingShape.upperTriad]: menor para as qualidades
/// menores, maior para as outras.
int _triadThird(ChordQuality quality) => switch (quality) {
  ChordQuality.minor ||
  ChordQuality.diminished ||
  ChordQuality.halfDiminished7 ||
  ChordQuality.diminished7 ||
  ChordQuality.minor7 ||
  ChordQuality.minorMajor7 ||
  ChordQuality.minor6 => 3,
  _ => 4,
};

/// Fundamental, 3ª e 7ª embaixo; as outras notas do acorde em cima, cada
/// uma subindo uma oitava se estiver abaixo da 5ª.
List<int>? _splitExt(ChordSymbol chord) {
  final third = chord.third;
  final seventh = chord.seventh;
  if (third == null || seventh == null) return null;
  final extensions = [
    for (final interval in chord.intervals)
      if (interval != 0 &&
          interval != third &&
          interval != chord.fifth &&
          interval != seventh)
        interval,
  ];
  final upper = [
    chord.fifth,
    ...extensions,
  ].map((x) => x < 12 ? x + 12 : x).toList()..sort();
  return [0, third, seventh, ...upper];
}

/// Os voicings do molde com a fundamental (ou a nota pedida) no baixo, de
/// [lowest] a [highest]. Cada um é a lista de alturas MIDI, de baixo para
/// cima.
List<List<int>> _placements(
  ChordSymbol chord,
  List<int> offsets, {
  required VoicingShape shape,
  required Inversion inversion,
  required int lowest,
  required int highest,
}) {
  var voices = [...offsets]..sort();
  final bass = chord.bass;
  final bassRel = bass == null ? null : _mod12(bass - chord.root);
  if (bassRel != null && !voices.any((v) => _mod12(v) == bassRel)) {
    // O baixo do acorde não é uma das notas do molde: ele entra embaixo.
    final extra = bassRel > voices.first ? bassRel - 12 : bassRel;
    voices = [extra, ...voices];
  }
  final moldeBass = inversion == Inversion.root
      ? _moldeBass(shape, chord)
      : null;
  final wanted =
      bassRel ??
      moldeBass ??
      switch (inversion) {
        Inversion.root => 0,
        Inversion.first => chord.third,
        Inversion.second => chord.fifth,
        Inversion.third => chord.seventh,
        Inversion.any => null,
      };
  var indices = [
    for (var k = 0; k < voices.length; k++)
      if (wanted == null || _mod12(voices[k]) == _mod12(wanted)) k,
  ];
  if (indices.isEmpty) indices = [0];

  final result = <List<int>>[];
  for (final k in indices) {
    final relative = _rotate(voices, k);
    final bassPitchClass = _mod12(chord.root + voices[k]);
    for (var m = lowest; m + relative.last <= highest; m++) {
      if (_mod12(m) != bassPitchClass) continue;
      result.add([for (final r in relative) m + r]);
    }
  }
  return result;
}

/// A nota que um molde põe embaixo por conta própria (quando a inversão é a
/// `root`, a padrão): a 7ª no `upperTriad`, e a 5ª no `drop2`, que é a que
/// desce. `null` nos outros, que põem a fundamental embaixo.
int? _moldeBass(VoicingShape shape, ChordSymbol chord) => switch (shape) {
  VoicingShape.upperTriad => chord.seventh,
  VoicingShape.drop2 => chord.fifth,
  _ => null,
};

/// Os intervalos com [voices][k] como fundamental do voicing: de 0 para
/// cima, em ordem, sem repetir nota.
List<int> _rotate(List<int> voices, int k) {
  final base = voices[k];
  final relative = {for (final v in voices) _upward(v - base)};
  return relative.toList()..sort();
}

int _upward(int d) => d >= 0 ? d : d + 12 * ((-d + 11) ~/ 12);

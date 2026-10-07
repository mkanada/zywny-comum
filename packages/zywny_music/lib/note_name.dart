import 'package:meta/meta.dart';

const _stepIndex = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
const _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const _diatonicIndex = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};

final _pitchPattern = RegExp(r'^([A-G])([#b]?)(\d)$');

/// Menor e maior tecla do piano (A0 e C8), em número MIDI.
const kLowestPianoMidi = 21;
const kHighestPianoMidi = 108;

/// Uma nota escrita como no arquivo do curso (notação científica):
/// `C4` = dó central, `F#4`, `Bb3`. Um sustenido ou um bemol, no máximo.
@immutable
class Pitch implements Comparable<Pitch> {
  const Pitch(this.step, this.alter, this.octave);

  /// A nota de [text], ou `null` se não for uma nota.
  static Pitch? tryParse(String text) {
    final match = _pitchPattern.firstMatch(text);
    if (match == null) return null;
    final alter = switch (match.group(2)) {
      '#' => 1,
      'b' => -1,
      _ => 0,
    };
    final pitch = Pitch(match.group(1)!, alter, int.parse(match.group(3)!));
    if (pitch.midi < kLowestPianoMidi || pitch.midi > kHighestPianoMidi) {
      return null;
    }
    return pitch;
  }

  /// Como [tryParse], mas com uma [FormatException] legível.
  factory Pitch.parse(String text) {
    final pitch = tryParse(text);
    if (pitch == null) throw FormatException(invalidMessage(text));
    return pitch;
  }

  /// "`H4` não é uma nota: …"
  static String invalidMessage(String text) =>
      '`$text` não é uma nota: use de C a B, com # ou b, e a oitava, como C4 '
      '(o piano vai de A0 a C8).';

  /// Letra da nota, de `C` a `B`.
  final String step;

  /// -1 bemol, 0 natural, 1 sustenido.
  final int alter;
  final int octave;

  /// Número MIDI: C4 = 60.
  int get midi => (octave + 1) * 12 + _stepIndex[step]! + alter;

  /// Posição na escala de naturais (C0 = 0, D0 = 1, …). A pauta alterna
  /// linha e espaço a cada passo, e a conta é a mesma nas duas claves: nota
  /// de índice par fica numa linha (a suplementar do dó central inclusa).
  int get diatonic => octave * 7 + _diatonicIndex[step]!;

  bool get isNatural => alter == 0;

  /// Fica numa linha da pauta (ou suplementar), não num espaço.
  bool get onLine => diatonic.isEven;

  @override
  int compareTo(Pitch other) => midi.compareTo(other.midi);

  @override
  bool operator ==(Object other) =>
      other is Pitch &&
      other.step == step &&
      other.alter == alter &&
      other.octave == octave;

  @override
  int get hashCode => Object.hash(step, alter, octave);

  @override
  String toString() =>
      '$step${alter > 0
          ? '#'
          : alter < 0
          ? 'b'
          : ''}$octave';
}

/// Faixa de notas `C4-G5`, inclusiva nas duas pontas (por número MIDI).
@immutable
class NoteRange {
  const NoteRange(this.from, this.to);

  /// A faixa de [text] ou `null` se estiver mal escrita ou invertida.
  static NoteRange? tryParse(String text) {
    final parts = text.split('-');
    if (parts.length != 2) return null;
    final from = Pitch.tryParse(parts[0].trim());
    final to = Pitch.tryParse(parts[1].trim());
    if (from == null || to == null || from.midi > to.midi) return null;
    return NoteRange(from, to);
  }

  factory NoteRange.parse(String text) {
    final range = tryParse(text);
    if (range == null) {
      throw FormatException(
        '`$text` não é uma faixa de notas: escreva da mais grave para a mais '
        'aguda, como C4-G5.',
      );
    }
    return range;
  }

  final Pitch from;
  final Pitch to;

  bool contains(Pitch pitch) =>
      pitch.midi >= from.midi && pitch.midi <= to.midi;

  /// Notas naturais da faixa, da mais grave para a mais aguda.
  List<Pitch> get naturals {
    final result = <Pitch>[];
    for (var d = from.diatonic; d <= to.diatonic; d++) {
      final pitch = Pitch(_steps[d % 7], 0, d ~/ 7);
      if (contains(pitch)) result.add(pitch);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is NoteRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from-$to';
}

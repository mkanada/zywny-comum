part of 'course_model.dart';

class FindKeySpec extends ExerciseSpec {
  const FindKeySpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.notes,
    required this.octave,
  });

  @override
  ExerciseType get type => ExerciseType.findKey;

  final NotesSpec notes;
  final OctaveRule octave;
}

class PlayNotesSpec extends ExerciseSpec {
  const PlayNotesSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.clef,
    required this.notes,
    required this.accidentals,
    this.key,
  });

  @override
  ExerciseType get type => ExerciseType.playNotes;

  final Clef clef;
  final String? key;
  final NotesSpec notes;
  final Accidentals accidentals;
}

class NameNoteSpec extends ExerciseSpec {
  const NameNoteSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.clef,
    required this.notes,
    required this.choices,
    this.key,
  });

  @override
  ExerciseType get type => ExerciseType.nameNote;

  final Clef clef;
  final String? key;
  final NotesSpec notes;

  /// Letras dos botões (`C`…`B`), na ordem do autor.
  final List<String> choices;
}

class RhythmSpec extends ExerciseSpec {
  const RhythmSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.time,
    required this.bpm,
    required this.note,
    required this.hands,
    required this.split,
    this.figures,
    this.measures,
    this.abc,
    this.groove,
    this.right,
    this.left,
  }) : assert(
         (hands == 2) == (left != null),
         'a mão esquerda existe só com duas mãos',
       );

  @override
  ExerciseType get type => ExerciseType.rhythm;

  final String time;
  final int bpm;

  /// A altura única tocada no sorteio (padrão C4).
  final Pitch note;

  /// Sorteio: figuras permitidas e quantos compassos…
  final List<Figure>? figures;
  final int? measures;

  /// …ou o ritmo escrito pelo autor.
  final String? abc;

  /// EX13: quantas mãos tocam, 1 ou 2. Com 2, a rodada é uma `TimedRound`
  /// (EX10), e a mão de cada toque sai do [split].
  final int hands;

  /// EX13: a nota que separa as mãos (padrão C4).
  final Pitch split;

  /// EX13: o groove da biblioteca (`kRhythmGrooves`), ou `null`. Com ele, o
  /// [right] e o [left] são os moldes do groove.
  final RhythmGroove? groove;

  /// EX13: os moldes da mão direita e da esquerda (`X . X | A . .`), uma lista
  /// de símbolos por compasso. O [left] é `null` quando a mão não toca.
  final List<List<RhythmSymbol>>? right;
  final List<List<RhythmSymbol>>? left;
}

class CountBeatsSpec extends ExerciseSpec {
  const CountBeatsSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.time,
    required this.figures,
    required this.count,
  });

  @override
  ExerciseType get type => ExerciseType.countBeats;

  final String time;
  final List<Figure> figures;
  final int count;
}

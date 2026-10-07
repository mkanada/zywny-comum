import 'package:meta/meta.dart';

import 'package:zywny_music/note_name.dart';

/// Valor do formato como aparece no arquivo (`type: play-notes`).
abstract interface class WireEnum {
  String get wire;
}

enum Clef implements WireEnum {
  treble,
  bass,
  grand;

  @override
  String get wire => name;
}

enum Accidentals implements WireEnum {
  none,
  sharps,
  flats,
  mixed;

  @override
  String get wire => name;
}

/// `only:` do sorteio de notas: só linhas ou só espaços da pauta.
enum OnlyOn implements WireEnum {
  lines,
  spaces;

  @override
  String get wire => name;
}

enum OctaveRule implements WireEnum {
  any,
  exact;

  @override
  String get wire => name;
}

enum HandChoice implements WireEnum {
  right,
  left,
  both;

  @override
  String get wire => name;
}

enum PlayMode implements WireEnum {
  wait,
  realtime;

  @override
  String get wire => name;
}

/// Figuras de ritmo. [eighths] é a duração em colcheias; pausas têm a mesma
/// duração da figura de mesmo nome.
enum Figure implements WireEnum {
  whole('whole', 8),
  half('half', 4),
  quarter('quarter', 2),
  eighth('eighth', 1),
  dottedHalf('dotted-half', 6),
  dottedQuarter('dotted-quarter', 3),
  wholeRest('whole-rest', 8, rest: true),
  halfRest('half-rest', 4, rest: true),
  quarterRest('quarter-rest', 2, rest: true),
  eighthRest('eighth-rest', 1, rest: true);

  const Figure(this.wire, this.eighths, {this.rest = false});

  @override
  final String wire;
  final int eighths;
  final bool rest;
}

enum ExerciseType implements WireEnum {
  findKey('find-key'),
  playNotes('play-notes'),
  nameNote('name-note'),
  rhythm('rhythm'),
  countBeats('count-beats'),
  playScore('play-score'),
  choice('choice');

  const ExerciseType(this.wire);

  @override
  final String wire;
}

/// Um curso lido: `course.md` mais as lições na ordem de `lessons`.
@immutable
class Course {
  const Course({
    required this.format,
    required this.id,
    required this.title,
    required this.author,
    required this.version,
    required this.intro,
    required this.lessons,
  });

  final int format;
  final String id;
  final String title;
  final String author;

  /// Sempre texto, mesmo que o arquivo traga um número (`version: 1`).
  final String version;

  /// O markdown da apresentação (o corpo de `course.md`).
  final String intro;
  final List<Lesson> lessons;
}

@immutable
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.requires,
    required this.fileName,
    required this.blocks,
  });

  final String id;
  final String title;

  /// Lições sugeridas antes desta (sempre anteriores na ordem do curso).
  final List<String> requires;

  /// Caminho em `lessons/`, para mensagens e para achar o arquivo.
  final String fileName;
  final List<LessonBlock> blocks;

  Iterable<ExerciseSpec> get exercises =>
      blocks.whereType<ExerciseMark>().map((mark) => mark.spec);
}

/// Um pedaço da lição, na ordem em que aparece: texto ou uma marca.
sealed class LessonBlock {
  const LessonBlock(this.line);

  /// Linha (base 1) em que o bloco começa no arquivo.
  final int line;
}

class TextBlock extends LessonBlock {
  const TextBlock(this.markdown, super.line);

  final String markdown;
}

/// De onde vem uma partitura: ABC em linha ou um `.musicxml` da pasta.
sealed class ScoreSource {
  const ScoreSource();
}

class AbcSource extends ScoreSource {
  const AbcSource(this.abc);

  final String abc;

  /// ABC completo (`X:`), com cabeçalho do autor.
  bool get isComplete => abcIsComplete(abc);
}

class FileSource extends ScoreSource {
  const FileSource(this.path);

  final String path;
}

/// Um `abc:` que começa com `X:` é ABC completo; senão é só o corpo.
bool abcIsComplete(String abc) => abc.trimLeft().startsWith('X:');

class ScoreMark extends LessonBlock {
  const ScoreMark({
    required int line,
    required this.source,
    required this.clef,
    this.key,
    this.time,
    this.highlight = const [],
    this.caption,
  }) : super(line);

  final ScoreSource source;
  final Clef clef;
  final String? key;
  final String? time;
  final List<Pitch> highlight;
  final String? caption;
}

class KeyboardMark extends LessonBlock {
  const KeyboardMark({
    required int line,
    required this.from,
    required this.to,
    this.mark = const [],
    this.names = false,
    this.caption,
  }) : super(line);

  final Pitch from;
  final Pitch to;
  final List<Pitch> mark;

  /// Escrever o nome em todas as teclas brancas da faixa.
  final bool names;
  final String? caption;
}

class AudioMark extends LessonBlock {
  const AudioMark({required int line, required this.file, this.caption})
    : super(line);

  final String file;
  final String? caption;
}

class VideoMark extends LessonBlock {
  const VideoMark({required int line, required this.link, this.caption})
    : super(line);

  final String link;
  final String? caption;
}

class ExerciseMark extends LessonBlock {
  const ExerciseMark(this.spec, super.line);

  final ExerciseSpec spec;
}

/// Critérios de aceite (`pass`), já com os padrões do formato.
@immutable
class PassCriteria {
  const PassCriteria({
    this.accuracy = 90,
    this.rounds = 1,
    this.speed = 100,
    this.timeLimit,
  });

  /// Porcentagem mínima numa rodada.
  final int accuracy;

  /// Rodadas aprovadas **seguidas**.
  final int rounds;

  /// Andamento mínimo em % do escrito; só vale onde há tempo real.
  final int speed;

  /// Segundos por pergunta; `null` = sem limite.
  final int? timeLimit;
}

/// Quais notas um exercício usa: lista fixa ou sorteio numa faixa.
sealed class NotesSpec {
  const NotesSpec();
}

class FixedNotes extends NotesSpec {
  const FixedNotes(this.notes);

  final List<Pitch> notes;
}

class RandomNotes extends NotesSpec {
  const RandomNotes({required this.range, required this.count, this.only});

  final NoteRange range;
  final int count;
  final OnlyOn? only;
}

/// Compassos escritos `5-12` (ou só `5`), base 1, inclusivos.
@immutable
class MeasureRange {
  const MeasureRange(this.from, this.to);

  final int from;
  final int to;

  @override
  String toString() => from == to ? '$from' : '$from-$to';
}

/// Um exercício; uma subclasse por `type`.
sealed class ExerciseSpec {
  const ExerciseSpec({
    required this.id,
    required this.title,
    required this.pass,
    required this.line,
  });

  ExerciseType get type;

  final String id;
  final String title;
  final PassCriteria pass;

  /// Linha da marca no arquivo da lição.
  final int line;
}

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
    this.figures,
    this.measures,
    this.abc,
  });

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

class PlayScoreSpec extends ExerciseSpec {
  const PlayScoreSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.source,
    required this.hand,
    required this.mode,
    this.bpm,
    this.measures,
  });

  @override
  ExerciseType get type => ExerciseType.playScore;

  final ScoreSource source;
  final HandChoice hand;
  final PlayMode mode;
  final int? bpm;
  final MeasureRange? measures;
}

class ChoiceSpec extends ExerciseSpec {
  const ChoiceSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.question,
    required this.options,
    required this.answer,
    this.image,
    this.abc,
  });

  @override
  ExerciseType get type => ExerciseType.choice;

  final String question;
  final List<String> options;

  /// Índice (base 0) da resposta certa em [options].
  final int answer;
  final String? image;
  final String? abc;
}

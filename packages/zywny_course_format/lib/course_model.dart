import 'package:meta/meta.dart';

import 'package:zywny_music/backing_styles.dart';
import 'package:zywny_music/chord.dart';
import 'package:zywny_music/comping_patterns.dart';
import 'package:zywny_music/note_name.dart';
import 'package:zywny_music/rhythm_grooves.dart';
import 'package:zywny_music/scale.dart';

part 'course_model_basics.dart';
part 'course_model_score.dart';
part 'course_model_chords.dart';
part 'course_model_melody.dart';
part 'course_model_echo.dart';

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

/// `listen-note`: como o aluno responde.
enum AnswerInput implements WireEnum {
  keyboard,
  buttons;

  @override
  String get wire => name;
}

/// `listen-interval`: os intervalos que o aluno pode ouvir. [semitones] é a
/// distância; o nome não pode ser `Interval` (colide com o do Flutter).
enum IntervalName implements WireEnum {
  m2('m2', 1),
  // ignore: constant_identifier_names
  M2('M2', 2),
  m3('m3', 3),
  // ignore: constant_identifier_names
  M3('M3', 4),
  // ignore: constant_identifier_names
  P4('P4', 5),
  // ignore: constant_identifier_names
  TT('TT', 6),
  // ignore: constant_identifier_names
  P5('P5', 7),
  m6('m6', 8),
  // ignore: constant_identifier_names
  M6('M6', 9),
  m7('m7', 10),
  // ignore: constant_identifier_names
  M7('M7', 11),
  // ignore: constant_identifier_names
  P8('P8', 12);

  const IntervalName(this.wire, this.semitones);

  @override
  final String wire;
  final int semitones;
}

/// `listen-interval`: a segunda nota fica acima, abaixo ou para os dois lados
/// (sorteado).
enum IntervalDirection implements WireEnum {
  up,
  down,
  both;

  @override
  String get wire => name;
}

/// `listen-interval`: uma depois da outra (melódico) ou juntas (harmônico).
enum IntervalPlay implements WireEnum {
  melodic,
  harmonic;

  @override
  String get wire => name;
}

/// `listen-score`: o que muda entre o escrito e o que soa.
enum ScoreChange implements WireEnum {
  pitch,
  rhythm,
  accidental;

  @override
  String get wire => name;
}

/// `listen-score`: como o aluno responde. `note` (E10) é tocar na nota da
/// partitura que soou diferente. `dictation` (E09) dá o ritmo e pede as notas,
/// tocadas no teclado; não tem diferença a achar.
enum ScoreAnswer implements WireEnum {
  measure('measure'),
  sameDifferent('same-different'),
  note('note'),
  dictation('dictation');

  const ScoreAnswer(this.wire);

  @override
  final String wire;
}

enum HandChoice implements WireEnum {
  right,
  left,
  both,

  /// `hand: sequence` (EX22): esquerda, depois direita, depois juntas a 80% do
  /// andamento. As duas primeiras só precisam passar em `accuracy`.
  sequence;

  @override
  String get wire => name;
}

enum PlayMode implements WireEnum {
  wait,
  realtime,

  /// O modo espera em que cada nota tem de ficar apertada pelo tempo dela
  /// (ND00, "notas com duração"): sem contagem nem metrônomo, como o `wait`,
  /// mas a nota só fecha depois de segurada.
  hold;

  @override
  String get wire => name;

  /// O andamento (`speed` do `pass`) vale: o tempo real e o `hold` (a duração
  /// de cada nota no relógio depende dele). O `wait` não tem relógio.
  bool get hasTempo => this != PlayMode.wait;

  /// O app espera cada nota antes de seguir (sem contagem nem metrônomo ligado
  /// de início): o `wait` e o `hold`. O `realtime` anda sozinho.
  bool get waitsForNotes => this != PlayMode.realtime;
}

/// `practice:` do `play-score` (EX22, Pike 27): a prática acumulativa. Hoje só
/// `cumulative`: cada compasso sozinho até o tempo forte do seguinte, depois
/// dois compassos, depois a passagem completa.
enum PracticeChoice implements WireEnum {
  cumulative;

  @override
  String get wire => name;
}

/// `tempo-ladder:` no `pass` (EX22, Pike 19): o andamento sobe `step` bpm a
/// cada rodada limpa e desce `back` a cada rodada reprovada, sem passar de
/// [to] nem descer de [from]. O exercício passa quando uma rodada limpa sai em
/// [to].
@immutable
class TempoLadder {
  const TempoLadder({
    required this.from,
    required this.to,
    required this.step,
    required this.back,
  });

  /// O andamento da primeira rodada, e o piso (bpm).
  final int from;

  /// A meta (bpm).
  final int to;

  /// Quanto sobe a cada rodada limpa (bpm).
  final int step;

  /// Quanto desce a cada rodada reprovada (bpm).
  final int back;
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

/// `play-chord`: a inversão pedida. `any` não confere; `random` sorteia uma
/// das que a cifra tem, e a pergunta diz qual.
enum ChordInversionChoice implements WireEnum {
  any,
  root,
  first,
  second,
  third,
  random;

  @override
  String get wire => name;
}

/// `play-chord`: a mão do acorde. `left` pede as notas abaixo do `split`;
/// `right`, as a partir dele.
enum ChordHand implements WireEnum {
  left,
  right,
  any;

  @override
  String get wire => name;
}

/// `play-chord`: o que a pergunta mostra (a cifra, o grau ou o nome).
enum ChordPrompt implements WireEnum {
  symbol('symbol'),
  degree('degree'),
  chordName('name');

  const ChordPrompt(this.wire);

  @override
  final String wire;
}

/// `listen-chord`: o que a pergunta pede: a qualidade do acorde (botões com o
/// nome) ou se ele é casa ou tensão, depois da cadência de referência
/// (`function`).
enum ChordAnswerKind implements WireEnum {
  quality,
  function;

  @override
  String get wire => name;
}

/// `listen-chord`: como o acorde soa: de uma vez (`block`), de baixo para cima
/// (`arpeggio`) ou o arpejo e depois o bloco (`both`).
enum ChordPlay implements WireEnum {
  block,
  arpeggio,
  both;

  @override
  String get wire => name;
}

/// `listen-progression` (EX15): como o aluno responde. Os botões mostram os
/// graus da progressão (`choice`), ou ele toca no teclado a fundamental de cada
/// acorde, em ordem (`bass`).
enum ProgressionAnswer implements WireEnum {
  choice,
  bass;

  @override
  String get wire => name;
}

/// `listen-groove` (EX13): o groove que a pergunta toca. O som é a base do EX12
/// no estilo do groove (`straight`, `shuffle`, `salsa-3-2`…).
enum ListenGroove implements WireEnum {
  straightEighths('straight-eighths'),
  swingEighths('swing-eighths'),
  shuffle128('shuffle-12-8'),
  clave32('clave-3-2'),
  clave23('clave-2-3'),
  bossa('bossa'),
  samba('samba'),
  waltz('waltz'),
  sixEight('six-eight');

  const ListenGroove(this.wire);

  @override
  final String wire;
}

enum ExerciseType implements WireEnum {
  findKey('find-key'),
  playNotes('play-notes'),
  nameNote('name-note'),
  rhythm('rhythm'),
  countBeats('count-beats'),
  playScore('play-score'),
  choice('choice'),
  listenNote('listen-note'),
  listenInterval('listen-interval'),
  listenScore('listen-score'),
  playChord('play-chord'),
  listenChord('listen-chord'),
  playPattern('play-pattern'),
  playChart('play-chart'),
  listenGroove('listen-groove'),
  echo('echo'),
  listenProgression('listen-progression'),
  harmonize('harmonize'),
  playLeadSheet('play-lead-sheet'),
  targetNotes('target-notes'),
  followForm('follow-form'),
  theoryQuiz('theory-quiz');

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
    this.chordNotation,
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

  /// A grafia da cifra fixada pelo curso (`chord-notation:`); `null` segue a
  /// configuração do app (D-EXE-CIFRA).
  final ChordNotation? chordNotation;
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

/// Uma grade de acordes (`zywny-chart`, EX09): o texto da grade ([chart]) ou o
/// nome de uma progressão da biblioteca ([progression]), no tom [key] e no
/// compasso [time] (como `C`, `4/4`, `6/8`). O pacote guarda o texto; quem lê
/// a grade é o app (`ChordChart.parse`).
class ChartMark extends LessonBlock {
  const ChartMark({
    required int line,
    required this.key,
    required this.time,
    this.chart,
    this.progression,
    this.bars,
    this.degrees = false,
    this.caption,
  }) : super(line);

  final String key;
  final String time;

  /// O texto da grade, ou `null` quando a marca usa [progression].
  final String? chart;
  final String? progression;

  /// Quantos compassos a [progression] ocupa (ela se repete até completar).
  final int? bars;

  /// Mostrar os graus (`ii7`, `V7`) em vez das cifras.
  final bool degrees;
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
    this.legato,
    this.staccato,
    this.dynamics = false,
    this.balance,
    this.pedal,
    this.steadiness,
    this.swing,
    this.accents,
    this.choruses,
    this.source,
    this.tempoLadder,
  });

  /// Porcentagem mínima numa rodada.
  final int accuracy;

  /// Rodadas aprovadas **seguidas**.
  final int rounds;

  /// Andamento mínimo em % do escrito; só vale onde há tempo real.
  final int speed;

  /// Segundos por pergunta; `null` = sem limite.
  final int? timeLimit;

  // Medidores (EX08). `null` é o que o autor não pediu: o medidor não aparece
  // no resumo nem reprova a rodada.

  /// % mínima de ligações limpas.
  final int? legato;

  /// % mínima de staccatos curtos.
  final int? staccato;

  /// Os trechos de dinâmica precisam estar certos (% mínima fixa em 80).
  final bool dynamics;

  /// Diferença mínima de força (velocity), melodia sobre acompanhamento.
  final int? balance;

  /// % mínima de trocas de pedal limpas.
  final int? pedal;

  /// Desvio-padrão máximo dos ataques, em ms.
  final int? steadiness;

  /// Faixa da razão da segunda colcheia de cada tempo, em % (`60-70`).
  final (int, int)? swing;

  /// Diferença mínima de força nos acentos.
  final int? accents;

  /// Voltas seguidas sem erro.
  final int? choruses;

  /// % mínima das notas entre os alvos que saíram da fonte (EX18, com
  /// `between: source` ou `free`).
  final int? source;

  /// O andamento que sobe e desce por rodada (EX22). Com ele, [speed] não vale:
  /// o andamento é o da escada.
  final TempoLadder? tempoLadder;
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

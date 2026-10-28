import 'package:meta/meta.dart';

import 'package:zywny_music/chord.dart';
import 'package:zywny_music/note_name.dart';
import 'package:zywny_music/scale.dart';

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
  playPattern('play-pattern');

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

/// `keys:` do `play-score` (EX05): os tons em que a partitura toca, rodada a
/// rodada. Ausente, a partitura toca no tom escrito.
sealed class KeyChoice {
  const KeyChoice();
}

/// `keys: [C, G, F]`: os tons na ordem escrita; a rodada N usa o N-ésimo.
class FixedKeys extends KeyChoice {
  const FixedKeys(this.keys);

  final List<String> keys;
}

/// `keys: all`: os 12 tons, em ordem sorteada uma vez por sessão.
class AllKeys extends KeyChoice {
  const AllKeys();
}

/// `keys: random`: um tom sorteado a cada rodada.
class RandomKeys extends KeyChoice {
  const RandomKeys();
}

/// `cycle:` do `play-score` (EX05): a rodada N usa o N-ésimo tom do ciclo, a
/// partir do tom escrito (`5ths` desce em quintas, como o `cycle-5` do EX01).
enum KeyCycle implements WireEnum {
  fifths('5ths'),
  fourths('4ths'),
  chromatic('chromatic'),
  wholeTone('whole-tone');

  const KeyCycle(this.wire);

  @override
  final String wire;
}

/// `key-start:` (EX05): o ciclo ou a lista começa no tom escrito, ou num tom
/// diferente a cada dia (`rotate`, Pike 7).
enum KeyStart implements WireEnum {
  written,
  rotate;

  @override
  String get wire => name;
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
    this.keys,
    this.cycle,
    this.keyStart = KeyStart.written,
  });

  @override
  ExerciseType get type => ExerciseType.playScore;

  final ScoreSource source;
  final HandChoice hand;
  final PlayMode mode;
  final int? bpm;
  final MeasureRange? measures;

  /// `keys:` (EX05), ou `null` para o tom escrito. Não vale junto com [cycle].
  final KeyChoice? keys;

  /// `cycle:` (EX05), ou `null`. Não vale junto com [keys].
  final KeyCycle? cycle;

  /// `key-start:` (EX05): só vale com [keys] ou [cycle].
  final KeyStart keyStart;
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

class ListenNoteSpec extends ExerciseSpec {
  const ListenNoteSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.notes,
    required this.input,
    required this.octave,
    required this.choices,
    this.reference,
    this.key,
  });

  @override
  ExerciseType get type => ExerciseType.listenNote;

  final NotesSpec notes;

  /// Nota tocada antes de cada pergunta (`null` = sem referência).
  final Pitch? reference;

  final AnswerInput input;

  /// Só vale com [AnswerInput.keyboard].
  final OctaveRule octave;

  /// Letras dos botões (`C`…`B`); só vale com [AnswerInput.buttons].
  final List<String> choices;

  /// Tom do sorteio; só vale com [AnswerInput.keyboard].
  final String? key;
}

/// `listen-interval`: toca dois sons (melódico ou harmônico) e o aluno escolhe
/// o nome do intervalo num botão.
class ListenIntervalSpec extends ExerciseSpec {
  const ListenIntervalSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.notes,
    required this.intervals,
    required this.direction,
    required this.play,
  });

  @override
  ExerciseType get type => ExerciseType.listenInterval;

  /// Notas de partida: a primeira de cada par.
  final NotesSpec notes;

  /// Os botões, na ordem do arquivo.
  final List<IntervalName> intervals;

  final IntervalDirection direction;

  final IntervalPlay play;
}

/// `listen-score`: mostra uma partitura gerada por um passo do treino de
/// leitura, toca uma versão com uma diferença e o aluno diz onde. O pacote
/// não conhece os passos: [step] é só o nome (`1a` a `100d`), e quem confere
/// e monta a partitura é o app.
class ListenScoreSpec extends ExerciseSpec {
  const ListenScoreSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.step,
    required this.change,
    required this.answer,
    required this.count,
    required this.bpm,
  });

  @override
  ExerciseType get type => ExerciseType.listenScore;

  /// O nome do passo do treino de leitura, como `4c`.
  final String step;

  final ScoreChange change;

  final ScoreAnswer answer;

  /// Quantas perguntas (partituras novas) a rodada tem.
  final int count;

  /// Andamento da frase; `null` usa o do passo.
  final int? bpm;
}

/// `play-chord`: as cifras da rodada, uma lista fixa ou um sorteio. O pacote
/// guarda o texto; quem monta o acorde é o app (EX02).
sealed class ChordsSpec {
  const ChordsSpec();
}

/// As cifras que o autor escreveu, na ordem.
class FixedChords extends ChordsSpec {
  const FixedChords(this.symbols);

  final List<String> symbols;
}

/// Um acorde por pergunta, com qualidade e raiz sorteadas. Com [sequence]
/// diferente de `random`, as raízes seguem a sequência a partir de [key] e
/// [roots] não vale; sem [roots], qualquer raiz (ou só as brancas com
/// [whiteOnly]).
class RandomChords extends ChordsSpec {
  const RandomChords({
    required this.qualities,
    required this.count,
    required this.sequence,
    this.roots,
    this.whiteOnly = false,
    this.key = 'C',
  });

  final List<String> qualities;
  final List<String>? roots;
  final bool whiteOnly;
  final int count;
  final String sequence;

  /// O tom de partida das sequências (e a escala do `diatonic`).
  final String key;
}

/// Os graus de [degrees] em cada um dos [count] tons, na ordem de [sequence]
/// a partir de [key]: um acorde por grau e por tom.
class DegreeChords extends ChordsSpec {
  const DegreeChords({
    required this.degrees,
    required this.count,
    required this.sequence,
    this.key = 'C',
  });

  final List<String> degrees;
  final int count;
  final String sequence;
  final String key;
}

/// `play-chord`: o aluno toca o acorde pedido no teclado MIDI, e o app
/// confere as notas e o que mais o exercício pedir (EX02).
class PlayChordSpec extends ExerciseSpec {
  const PlayChordSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.chords,
    required this.inversions,
    required this.hand,
    required this.split,
    required this.strict,
    required this.omit5,
    required this.prompt,
    this.voicing,
    this.range,
    this.voiceLeading,
    this.bpm,
    this.beats = 4,
  });

  @override
  ExerciseType get type => ExerciseType.playChord;

  final ChordsSpec chords;

  /// Uma por acorde, em ciclo; com um item só, vale para todos.
  final List<ChordInversionChoice> inversions;

  /// O nome do molde (`close`, `7-3`…); `null` não confere o molde.
  final String? voicing;

  final ChordHand hand;

  /// A nota que separa as mãos (`left` fica abaixo, `right` a partir dela).
  final Pitch split;

  /// A faixa em que o acorde pode soar; `null` é o teclado todo.
  final NoteRange? range;

  /// Com `true`, a inversão e o molde pedidos batem exatamente (e o molde não
  /// aceita nota dobrada).
  final bool strict;

  /// A 5ª justa pode faltar nos acordes de sétima ou mais.
  final bool omit5;

  final ChordPrompt prompt;

  /// Movimento máximo, em semitons, de um acorde para o seguinte; acima disso
  /// o acorde vale, mas conta como erro de primeira.
  final int? voiceLeading;

  /// Andamento do modo com tempo (EX03): cada pergunta dura [beats] tempos e
  /// o metrônomo marca. `null` = sem tempo (a pergunta espera o aluno).
  final int? bpm;

  /// Tempos por acorde, no modo com tempo.
  final int beats;
}

/// `listen-chord` (EX04): o zywny toca um acorde e o aluno diz a qualidade
/// (botões com o nome) ou, com `answer: function`, se ele é casa ou tensão.
/// Sem teclado MIDI.
class ListenChordSpec extends ExerciseSpec {
  const ListenChordSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.answer,
    required this.count,
    required this.play,
    required this.inversion,
    required this.key,
    this.qualities = const [],
    this.roots,
    this.degrees = const [],
  });

  @override
  ExerciseType get type => ExerciseType.listenChord;

  final ChordAnswerKind answer;

  /// Quantas perguntas. Com `roots` em lista, uma por nota, e este valor não
  /// vale (o leitor recusa o `count` junto).
  final int count;

  /// `quality`: as qualidades, na ordem dos botões. Vazio no `function`.
  final List<String> qualities;

  /// `quality`: a fundamental de cada pergunta, sorteada ou em lista. `null` no
  /// `function`.
  final NotesSpec? roots;

  /// `quality`: como o acorde soa.
  final ChordPlay play;

  /// `quality`: `root`, ou `random` (sorteada entre as inversões que a
  /// qualidade tem).
  final ChordInversionChoice inversion;

  /// `function`: o tom (`C`, `Am`…), ou `random` para sortear um por pergunta.
  final String key;

  /// `function`: os graus que podem soar. Vazio no `quality`.
  final List<String> degrees;
}

/// `pattern:` do `play-pattern` (EX06): o padrão técnico que o app gera.
enum PatternKind implements WireEnum {
  fiveFinger('five-finger'),
  scale('scale'),
  arpeggio('arpeggio'),
  brokenChord('broken-chord'),
  diatonicChords('diatonic-chords'),
  threeNote('three-note'),
  sequence('sequence'),
  chromatic('chromatic');

  const PatternKind(this.wire);

  @override
  final String wire;
}

/// `hand:` do `play-pattern`: uma mão, as duas em oitavas paralelas, ou as
/// duas em movimento contrário.
enum PatternHand implements WireEnum {
  right,
  left,
  both,
  contrary;

  @override
  String get wire => name;
}

/// `direction:` do `play-pattern`: a escala sobe e desce, só sobe ou só desce.
enum PatternDirection implements WireEnum {
  upDown('up-down'),
  up('up'),
  down('down');

  const PatternDirection(this.wire);

  @override
  final String wire;
}

/// `articulation:` do `play-pattern` (Pearl 7, "articulação variada").
enum PatternArticulation implements WireEnum {
  legato('legato'),
  staccato('staccato'),
  twoSlurred('two-slurred'),
  accentFirst('accent-first');

  const PatternArticulation(this.wire);

  @override
  final String wire;
}

/// `grouping:` do `play-pattern`: o agrupamento rítmico das notas.
enum PatternGrouping implements WireEnum {
  four('4'),
  three('3'),
  two('2'),
  dotted('dotted'),
  swing('swing');

  const PatternGrouping(this.wire);

  @override
  final String wire;
}

/// `chords:` do `diatonic-chords`: as tríades ou as tétrades do campo harmônico.
enum PatternChords implements WireEnum {
  triads,
  sevenths;

  @override
  String get wire => name;
}

/// `style:` do `diatonic-chords`: em bloco ou quebrado.
enum PatternStyle implements WireEnum {
  block,
  broken;

  @override
  String get wire => name;
}

/// `figure:` do `broken-chord`: a ordem das notas do acorde quebrado.
enum PatternFigure implements WireEnum {
  figure1353('1353'),
  alberti('alberti'),
  figure15810('15810'),
  guitar('guitar'),
  blues('blues');

  const PatternFigure(this.wire);

  @override
  final String wire;
}

/// `order:` do `three-note`: a ordem das três notas do padrão (1, 2 e 3 são as
/// posições).
enum PatternOrder implements WireEnum {
  order123('123'),
  order132('132'),
  order213('213'),
  order231('231'),
  order312('312'),
  order321('321');

  const PatternOrder(this.wire);

  @override
  final String wire;
}

/// `source:` do `three-note`: as três notas são graus consecutivos da escala
/// (`scale`) ou as notas de cada tríade (`chord`).
enum PatternSource implements WireEnum {
  chord,
  scale;

  @override
  String get wire => name;
}

/// `play-pattern` (EX06): o app gera a partitura de um padrão técnico, em
/// qualquer tom, com o dedilhado e as articulações que o padrão pede.
class PlayPatternSpec extends ExerciseSpec {
  const PlayPatternSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.pattern,
    required this.scale,
    required this.chord,
    required this.chords,
    required this.style,
    required this.figure,
    required this.order,
    required this.source,
    required this.octaves,
    required this.direction,
    required this.hand,
    required this.fingering,
    required this.articulation,
    required this.grouping,
    required this.mode,
    required this.key,
    this.motif = const [],
    this.keys,
    this.cycle,
    this.keyStart = KeyStart.written,
    this.bpm,
  });

  @override
  ExerciseType get type => ExerciseType.playPattern;

  final PatternKind pattern;

  /// `scale:` (com `scale` e `three-note`): a escala de onde saem as notas.
  final ScaleKind scale;

  /// `chord:` (com `arpeggio` e `broken-chord`): a qualidade do acorde (`M`,
  /// `m`, `7`, `maj7`, `m7`, `m7b5`, `dim7`, `3-5-7-9`).
  final String chord;

  final PatternChords chords;
  final PatternStyle style;
  final PatternFigure figure;
  final PatternOrder order;
  final PatternSource source;

  /// `motif:` (com `sequence`): os graus do motivo, de 1 a 7, base 1.
  final List<int> motif;

  /// O tom do padrão (`key:`), quando não há `keys:` nem `cycle:`.
  final String key;

  /// `keys:` e `cycle:` (EX05), ou `null` para o tom de [key].
  final KeyChoice? keys;
  final KeyCycle? cycle;
  final KeyStart keyStart;

  /// De 1 a 4 oitavas.
  final int octaves;
  final PatternDirection direction;
  final PatternHand hand;

  /// `fingering:`: escreve o dedilhado quando o livro (ou a regra do padrão)
  /// tem um para o caso.
  final bool fingering;

  final PatternArticulation articulation;
  final PatternGrouping grouping;

  /// `mode:` e `bpm:`, como no `play-score`.
  final PlayMode mode;
  final int? bpm;
}

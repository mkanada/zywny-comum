part of 'course_model.dart';

/// `source:` do `echo` (EX14): de onde vêm as notas das frases que o app toca.
sealed class EchoSource {
  const EchoSource();
}

/// `{scale, key}`: notas sorteadas na escala, no tom [key], dentro da faixa do
/// exercício.
class EchoScaleSource extends EchoSource {
  const EchoScaleSource({required this.scale, required this.key});

  final ScaleKind scale;
  final String key;
}

/// `{chord-tones: true}`: as notas do acorde de cada compasso da grade.
class EchoChordSource extends EchoSource {
  const EchoChordSource();
}

/// `{licks: <biblioteca>}`: frases curtas de uma biblioteca de estilo (EX14),
/// escritas em graus da escala da biblioteca.
class EchoLickSource extends EchoSource {
  const EchoLickSource(this.library);

  /// O nome da biblioteca (`blues-basic`, `ii-v-major`…).
  final String library;
}

/// `transpose:` do `echo` (EX14): em que tom cada frase vem.
enum EchoTranspose implements WireEnum {
  none('none'),
  cycle5('cycle-5'),
  cycle4('cycle-4'),
  chromatic('chromatic'),
  random('random');

  const EchoTranspose(this.wire);

  @override
  final String wire;
}

/// `start:` do `echo` (EX14): a primeira nota da frase.
enum EchoStart implements WireEnum {
  tonic('tonic'),
  chordTone('chord-tone'),
  any('any');

  const EchoStart(this.wire);

  @override
  final String wire;
}

/// `octave:` do `echo` (EX14): `exact` pede a altura; `any` aceita a mesma nota
/// numa oitava qualquer.
enum EchoOctave implements WireEnum {
  exact('exact'),
  any('any');

  const EchoOctave(this.wire);

  @override
  final String wire;
}

/// `rhythm:` do `echo` (EX14): `loose` vê só a ordem e o contorno; `strict`
/// também confere o tempo de cada nota.
enum EchoRhythm implements WireEnum {
  loose('loose'),
  strict('strict');

  const EchoRhythm(this.wire);

  @override
  final String wire;
}

/// `echo` (EX14): o app toca uma frase curta, sobre a base ou o metrônomo, e o
/// aluno a repete no compasso seguinte, sem partitura. Cada frase ocupa
/// [measures] compassos de "OUÇA" e outros tantos de "TOQUE".
class EchoSpec extends ExerciseSpec {
  const EchoSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.source,
    required this.range,
    required this.notes,
    required this.figures,
    required this.measures,
    required this.leaps,
    required this.start,
    required this.bpm,
    required this.swing,
    required this.count,
    required this.octave,
    required this.transpose,
    required this.rhythm,
    required this.split,
    required this.hand,
    this.backing,
    this.chartText,
    this.progression,
    this.progressionBars,
    this.chartKey = 'C',
  });

  @override
  ExerciseType get type => ExerciseType.echo;

  final EchoSource source;

  /// A faixa das frases (`C4-C6` quando o autor não diz).
  final NoteRange range;

  /// Notas por frase (1 a 12). Não vale com `licks`.
  final int notes;

  /// As figuras que a frase pode ter. Não vale com `licks`.
  final List<Figure> figures;

  /// Compassos por frase (1 ou 2).
  final int measures;

  /// O maior salto, em graus da escala. Não vale com `licks`.
  final int leaps;

  /// Não vale com `licks`.
  final EchoStart start;

  final int bpm;

  /// 50 é reto; 67 é a tercina.
  final int swing;

  /// A base gerada (EX12) e o estilo; `null` sem `backing:`.
  final BackingSpec? backing;

  /// A grade do exercício (`chart:`): a escrita ([chartText]) ou a progressão da
  /// biblioteca ([progression], com [progressionBars] e [chartKey]). Obrigatória
  /// com `chord-tones`; sem ela, a base fica no acorde da tônica.
  final String? chartText;
  final String? progression;
  final int? progressionBars;
  final String chartKey;

  /// Quantas frases (1 a 40).
  final int count;

  final EchoOctave octave;
  final EchoTranspose transpose;
  final EchoRhythm rhythm;

  /// A altura que separa as mãos (D-EXE-MAOS).
  final Pitch split;

  /// A mão que responde: as teclas da outra mão não contam.
  final HandChoice hand;
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
    this.handSequence = false,
  });

  @override
  ExerciseType get type => ExerciseType.playPattern;

  /// `hand: sequence` (EX22): as rodadas são esquerda, direita e juntas (a 80%
  /// do andamento). O [hand] é `both` nesse caso, e o gerador troca a mão.
  final bool handSequence;

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

/// `topics:` do `theory-quiz` (EX21): os tópicos de teoria. A rodada divide as
/// perguntas entre eles. `formTemplate` está no formato, e o leitor o recusa
/// com "ainda não roda": a forma é texto das lições (fora do EX21).
enum TheoryTopic implements WireEnum {
  keySignature('key-signature'),
  sharpsOrder('sharps-order'),
  relativeMinor('relative-minor'),
  relativeMajor('relative-major'),
  parallel('parallel'),
  scaleDegree('scale-degree'),
  intervalName('interval-name'),
  intervalBuild('interval-build'),
  chordTones('chord-tones'),
  chordDegree('chord-degree'),
  degreeChord('degree-chord'),
  chordFromStaff('chord-from-staff'),
  circleNext('circle-next'),
  harmonicFunction('function'),
  functionByTritone('function-by-tritone'),
  blackKeyCount('black-key-count'),
  availableExtensions('available-extensions'),
  romanAnalysis('roman-analysis'),
  formTemplate('form-template');

  const TheoryTopic(this.wire);

  @override
  final String wire;
}

/// `answer:` do `theory-quiz` (EX21): os botões, ou o teclado nos tópicos em que
/// a resposta é uma nota ou um acorde (o resto segue com botões).
enum TheoryAnswer implements WireEnum {
  buttons('buttons'),
  keyboard('keyboard');

  const TheoryAnswer(this.wire);

  @override
  final String wire;
}

/// `theory-quiz` (EX21): perguntas de teoria geradas a cada rodada (armadura,
/// relativas, graus, funções, análise romana…). Cada tópico tem a sua fórmula;
/// as opções erradas vêm dos erros comuns dele.
class TheoryQuizSpec extends ExerciseSpec {
  const TheoryQuizSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.topics,
    required this.keys,
    required this.count,
    required this.answer,
    required this.qualities,
  });

  @override
  ExerciseType get type => ExerciseType.theoryQuiz;

  /// Os tópicos, na ordem do autor, sem repetir.
  final List<TheoryTopic> topics;

  /// As tônicas (`C`, `Bb`, `F#`), sem `m`: o modo vem do tópico. `all` são os
  /// 12 tons, já escritos aqui.
  final List<String> keys;

  /// Quantas perguntas (de 1 a 40).
  final int count;

  final TheoryAnswer answer;

  /// As qualidades dos tópicos de acorde (`M`, `m`, `7`…); o padrão é `[M, m]`.
  final List<String> qualities;
}

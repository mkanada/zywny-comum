import 'package:meta/meta.dart';
import 'package:zywny_music/backing_styles.dart';
import 'package:zywny_music/chord_voicing.dart';
import 'package:zywny_music/rhythm_grooves.dart';
import 'package:zywny_music/scale.dart';

import 'course_model.dart';

/// O vocabulário do formato v1 como **dados**: as tabelas do I00 e de
/// `docs/licoes/formato-v1.md`. O leitor (`course_reader.dart`) valida contra
/// elas e o teste de cobertura do curso inicial (I11) lê delas — uma fonte
/// só. Chave nova entra aqui, na especificação e no curso inicial.

/// Como um valor é lido e conferido.
enum ValueType {
  /// Texto não vazio (só `String`).
  text,

  /// Texto, número ou booleano escrito sem aspas; guardado como texto.
  scalarText,

  /// Identificador `^[a-z0-9-]{1,40}$`.
  id,
  integer,
  boolean,

  /// Uma das palavras de [KeyDef.values].
  option,
  note,
  noteList,

  /// Lista fixa de notas ou sorteio `{random: C4-G5, count: 12}`.
  notes,

  /// Letras de `C` a `B` (os botões do `name-note`).
  letterList,
  figureList,

  /// Lista de textos (aceita números sem aspas, guardados como texto).
  stringList,

  /// Arquivo da pasta do curso, com extensão de [KeyDef.extensions].
  path,

  /// `https://…`
  link,
  keyName,

  /// `keys:` do `play-score` (EX05): `all`, `random` ou uma lista de tons.
  keyChoice,
  timeSignature,

  /// `5-12` ou `5`.
  measureRange,

  /// `60-70`: uma faixa crescente de inteiros, entre `min` e `max` (`swing`).
  intRange,

  /// ABC em linha (texto, em geral um bloco `|`).
  abc,

  /// O mapa `pass:`.
  passMap,

  /// `chords:` do `play-chord`: uma lista de cifras ou o mapa do sorteio.
  chordsSpec,

  /// Uma palavra de [KeyDef.values], ou uma lista delas (`inversion:`).
  optionOrList,

  /// `chart:` do `play-chart` (EX11): a grade escrita (texto) ou o mapa
  /// `{progression, key, bars}`.
  chartSpec,

  /// `pattern:` do `play-chart` (EX11): um nome da biblioteca (texto) ou o
  /// mapa `{grid, left, right}`.
  patternSpec,

  /// `backing:` do `play-chart` (EX12): o texto `drums` ou o mapa
  /// `{style, drums, bass, volume, intro}`.
  backingSpec,

  /// `source:` do `echo` (EX14): o mapa `{scale, key}`, `{chord-tones: true}`
  /// ou `{licks: <biblioteca>}`, com `range` onde couber.
  echoSource,

  /// `melody:` do `harmonize` (EX16): o mapa `{step, key}` ou `{file}`.
  melodySpec,

  /// `enter:` do `follow-form` (EX20): o mapa `{bars, pattern}` ou `{section,
  /// pattern}`.
  enterSpec,
}

@immutable
class KeyDef {
  const KeyDef(
    this.type, {
    this.required = false,
    this.values = const [],
    this.min,
    this.max,
    this.extensions = const [],
    this.minItems = 0,
    this.fallback,
  });

  final ValueType type;
  final bool required;

  /// Palavras aceitas (`ValueType.option`).
  final List<String> values;

  /// Limites de um `integer`.
  final int? min;
  final int? max;

  /// Extensões aceitas de um `path`, com ponto e minúsculas.
  final List<String> extensions;

  /// Tamanho mínimo de uma lista.
  final int minItems;

  /// O padrão, escrito como na especificação (só documentação e testes).
  final String? fallback;
}

List<String> _wires(List<WireEnum> values) => [
  for (final value in values) value.wire,
];

const kIdPattern = r'^[a-z0-9-]{1,40}$';

/// O maior `format` que este app lê.
const kCourseFormat = 1;

/// Tons que o formato aceita em `key`: maiores e menores com `m`.
const kKeyNames = [
  'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#', //
  'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Cb',
  'Am', 'Em', 'Bm', 'F#m', 'C#m', 'G#m', 'D#m', 'A#m', //
  'Dm', 'Gm', 'Cm', 'Fm', 'Bbm', 'Ebm', 'Abm',
];

const kTimeSignatures = ['4/4', '3/4', '2/4', '6/8', 'C'];

/// Duração de um compasso, em colcheias.
int measureEighths(String time) => switch (time) {
  '3/4' || '6/8' => 6,
  '2/4' => 4,
  _ => 8,
};

const kImageExtensions = ['.png', '.jpg', '.webp'];
const kAudioExtensions = ['.ogg', '.mp3'];
const kScoreExtensions = ['.musicxml'];

KeyDef _clef() =>
    KeyDef(ValueType.option, values: _wires(Clef.values), fallback: 'treble');

/// `grand` não existe na marca `zywny-score`: o ABC não desenha duas pautas e
/// com `file:` a pauta vem do `.musicxml`.
const _scoreClef = KeyDef(
  ValueType.option,
  values: ['treble', 'bass'],
  fallback: 'treble',
);

const _caption = KeyDef(ValueType.text);
const _key = KeyDef(ValueType.keyName);
const _time = KeyDef(ValueType.timeSignature);
const _abc = KeyDef(ValueType.abc);

/// Chaves do front matter de `course.md`.
const kCourseKeys = <String, KeyDef>{
  'format': KeyDef(ValueType.integer, required: true, min: 1),
  'id': KeyDef(ValueType.id, required: true),
  'title': KeyDef(ValueType.text, required: true),
  'author': KeyDef(ValueType.text, required: true),
  'version': KeyDef(ValueType.scalarText, required: true),
  'lessons': KeyDef(ValueType.stringList, required: true, minItems: 1),
  // EX03 (D-EXE-CIFRA): a grafia da cifra que o curso fixa; sem a chave, vale
  // a configuração do app.
  'chord-notation': KeyDef(ValueType.option, values: ['american', 'brazilian']),
};

/// Chaves do front matter de uma lição.
const kLessonKeys = <String, KeyDef>{
  'id': KeyDef(ValueType.id, required: true),
  'title': KeyDef(ValueType.text, required: true),
  'requires': KeyDef(ValueType.stringList),
};

/// Marcas de conteúdo (as que abrem com `zywny-` e o nome), por nome sem o
/// prefixo.
/// `exercise` tem o vocabulário próprio em [exerciseKeys].
final kContentMarkKeys = <String, Map<String, KeyDef>>{
  'score': {
    'abc': _abc,
    'file': const KeyDef(ValueType.path, extensions: kScoreExtensions),
    'clef': _scoreClef,
    'key': _key,
    'time': _time,
    'highlight': const KeyDef(ValueType.noteList),
    'caption': _caption,
  },
  'keyboard': {
    'from': const KeyDef(ValueType.note, fallback: 'C3'),
    'to': const KeyDef(ValueType.note, fallback: 'C5'),
    'mark': const KeyDef(ValueType.noteList),
    'names': const KeyDef(ValueType.boolean, fallback: 'false'),
    'caption': _caption,
  },
  'audio': {
    'file': const KeyDef(
      ValueType.path,
      required: true,
      extensions: kAudioExtensions,
    ),
    'caption': _caption,
  },
  'video': {
    'link': const KeyDef(ValueType.link, required: true),
    'caption': _caption,
  },
  // EX09: a grade de acordes. Ou `chart` (o texto da grade) ou `progression`
  // (um nome da biblioteca do EX01), nunca os dois.
  'chart': {
    'key': const KeyDef(ValueType.keyName, fallback: 'C'),
    'time': const KeyDef(ValueType.timeSignature, fallback: '4/4'),
    'chart': const KeyDef(ValueType.text),
    'progression': const KeyDef(ValueType.text),
    'bars': const KeyDef(ValueType.integer, min: 1, max: 400),
    'degrees': const KeyDef(ValueType.boolean, fallback: 'false'),
    'caption': _caption,
  },
};

/// Nome da marca de exercício (sem o prefixo `zywny-`).
const kExerciseMark = 'exercise';

/// Todas as marcas, sem o prefixo `zywny-`.
final kMarkNames = [...kContentMarkKeys.keys, kExerciseMark];

/// Chaves do mapa `random:` de `notes`.
const kRandomNotesKeys = <String, KeyDef>{
  'random': KeyDef(ValueType.text, required: true),
  'count': KeyDef(ValueType.integer, min: 1, max: 60, fallback: '12'),
  'only': KeyDef(ValueType.option, values: ['lines', 'spaces']),
};

const _notes = KeyDef(ValueType.notes, required: true);

/// Fundamentais que `roots:` aceita, além de `random` e `white` (EX02).
const kRootNames = [
  'C',
  'C#',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// Qualidades de `qualities:` (EX00, "Cifra"), com o sufixo que o
/// `ChordSymbol.parse` lê depois da raiz.
const kChordQualities = <String, String>{
  'M': '',
  'm': 'm',
  'dim': 'dim',
  'aug': 'aug',
  '7': '7',
  'maj7': 'maj7',
  'm7': 'm7',
  'm7b5': 'm7b5',
  'dim7': 'dim7',
  '6': '6',
  'm6': 'm6',
  '9': '9',
  'sus2': 'sus2',
  'sus4': 'sus4',
  '7sus4': '7sus4',
};

/// Os moldes de `voicing:` (EX00, "Voicing") e o [VoicingShape] de cada um.
const kVoicingShapes = <String, VoicingShape>{
  'close': VoicingShape.close,
  'shell-17': VoicingShape.shell17,
  'shell-13': VoicingShape.shell13,
  '7-3': VoicingShape.sevenThree,
  '7-3-ext': VoicingShape.sevenThreeExt,
  'rootless-a': VoicingShape.rootlessA,
  'rootless-b': VoicingShape.rootlessB,
  'block': VoicingShape.block,
  'quartal': VoicingShape.quartal,
  'so-what': VoicingShape.soWhat,
  'tenth': VoicingShape.tenth,
  'upper-triad': VoicingShape.upperTriad,
  'two-hand-5': VoicingShape.twoHand5,
  'drop-2': VoicingShape.drop2,
  'split-ext': VoicingShape.splitExt,
};

/// As qualidades de `chord:` do `play-pattern` (EX06): as do `play-chord` mais
/// o `3-5-7-9` (o arpejo de jazz, Pike 26 e 27; Rawlins 8).
const kPatternChordQualities = [
  'M',
  'm',
  '7',
  'maj7',
  'm7',
  'm7b5',
  'dim7',
  '3-5-7-9',
];

/// As sequências de `sequence:` (EX00, "Ciclos e sequência de tons").
const kChordSequences = [
  'random',
  'cycle-5',
  'cycle-4',
  'chromatic',
  'whole-tone',
  'diatonic',
];

/// Chaves do mapa `chords:` com um sorteio: `qualities` ou `degrees`, mais
/// as que valem nos dois.
/// O mapa `chart:` do `play-chart` (EX11), quando a grade vem da biblioteca.
const kChartMapKeys = <String, KeyDef>{
  'progression': KeyDef(ValueType.text, required: true),
  'key': _key,
  'bars': KeyDef(ValueType.integer, min: 1, max: 40),
};

/// O mapa `pattern:` do `play-chart` (EX11): o molde escrito no exercício.
/// `grid` é o número de partes do compasso; `left` e `right` são as linhas.
const kPatternMapKeys = <String, KeyDef>{
  'grid': KeyDef(ValueType.integer, required: true, min: 2, max: 16),
  'left': KeyDef(ValueType.text),
  'right': KeyDef(ValueType.text),
};

/// O mapa `backing:` do `play-chart` (EX12). `style` é o nome de um estilo da
/// tabela (`backing_styles.dart`); sem ele, o do molde de comping.
const kBackingMapKeys = <String, KeyDef>{
  'style': KeyDef(ValueType.text),
  'drums': KeyDef(ValueType.boolean, fallback: 'true'),
  'bass': KeyDef(
    ValueType.option,
    values: ['none', 'root', 'root-fifth', 'walking', 'pattern'],
    fallback: 'root-fifth',
  ),
  'volume': KeyDef(ValueType.integer, min: 0, max: 100, fallback: '70'),
  'intro': KeyDef(ValueType.integer, min: 0, max: 4, fallback: '1'),
};

/// As técnicas de rearmonização do `harmonize` (EX16, o modo `reharmonize`,
/// que ainda não roda). Ficam no vocabulário para o leitor dizer o que falta.
const kHarmonizeTechniques = [
  'diatonic-sub',
  'add-ii-v',
  'passing-dim',
  'tritone-sub',
  'line-cliche',
];

/// O mapa `enter:` do `follow-form` (EX20). `bars` (`11-12`) ou `section` (`B`)
/// dizem onde o aluno entra; `pattern` é o molde do que ele toca ali. O leitor
/// confere que haja um dos dois e que o padrão exista.
const kFollowEnterKeys = <String, KeyDef>{
  'bars': KeyDef(ValueType.measureRange),
  'section': KeyDef(ValueType.text),
  'pattern': KeyDef(ValueType.text, required: true),
};

/// O mapa `melody:` do `harmonize` (EX16). `step` e `key` geram a melodia; `file`
/// é o `.musicxml` da pasta. O leitor confere que haja uma das duas formas.
const kMelodyMapKeys = <String, KeyDef>{
  'step': KeyDef(ValueType.text),
  'key': _key,
  'file': KeyDef(ValueType.path, extensions: kScoreExtensions),
};

/// As bibliotecas de licks do `echo` (EX14). O conteúdo de cada uma está no app
/// (`lib/course/exercise/lick_library.dart`), que confere que os nomes batem.
const kLickLibraryNames = [
  'blues-basic',
  'blues-crossover',
  'rock-pentatonic',
  'country-major-pent',
  'ii-v-major',
  'ii-v-minor',
  'bebop-enclosure',
  'gospel-fills',
  'montuno-figures',
];

/// O mapa `source:` do `echo` (EX14). Sem `scale`, `chord-tones` nem `licks`, o
/// leitor do exercício diz o que falta.
final kEchoSourceKeys = <String, KeyDef>{
  'scale': KeyDef(
    ValueType.option,
    values: [for (final scale in ScaleKind.values) scale.wire],
  ),
  'key': _key,
  'chord-tones': KeyDef(ValueType.boolean),
  'licks': KeyDef(ValueType.option, values: kLickLibraryNames),
  'range': KeyDef(ValueType.text),
};

final kChordRandomKeys = <String, KeyDef>{
  'qualities': const KeyDef(ValueType.stringList, minItems: 1),
  'degrees': const KeyDef(ValueType.stringList, minItems: 1),
  'roots': KeyDef(
    ValueType.optionOrList,
    values: [...kRootNames, 'random', 'white'],
    fallback: 'random',
  ),
  'key': _key,
  'sequence': KeyDef(
    ValueType.option,
    values: kChordSequences,
    fallback: 'random',
  ),
  'count': const KeyDef(ValueType.integer, min: 1, max: 40),
};

/// Chaves de `pass` e em que tipos cada uma vale (I00, "Critérios de aceite").
@immutable
class PassKey {
  const PassKey(this.def, this.types, {this.note, this.realtimeOnly = false});

  final KeyDef def;
  final Set<ExerciseType> types;

  /// Explicação extra para a mensagem de "não vale aqui".
  final String? note;

  /// Só vale com tempo real: o andamento (`speed`) e os medidores que leem o
  /// tempo que o aluno tocou (EX08). No modo espera, o relógio não para no
  /// freio, então esses tempos não batem com a partitura.
  final bool realtimeOnly;
}

/// Os tipos com tempo: a conferência do `pass` sabe o que é tocar no tempo.
const _timedTypes = {
  ExerciseType.rhythm,
  ExerciseType.playScore,
  ExerciseType.playPattern,
};

/// As qualidades de `qualities:` do `theory-quiz` (EX21): as de
/// `kChordQualities`, sem a 9ª (que pede a tensão a mais).
const kTheoryQualities = [
  'M',
  'm',
  'dim',
  'aug',
  '7',
  'maj7',
  'm7',
  'm7b5',
  'dim7',
  '6',
  'm6',
  'sus2',
  'sus4',
  '7sus4',
];

/// Os 12 tons de `keys: all` no `theory-quiz` (EX21), com a grafia que cada um
/// leva: `F#` (e não `Gb`), `Db` (e não `C#`).
const kTheoryAllKeys = [
  'C',
  'G',
  'D',
  'A',
  'E',
  'B',
  'F#',
  'F',
  'Bb',
  'Eb',
  'Ab',
  'Db',
];

/// A regularidade, o swing e as voltas (EX08) valem também no `play-chart`
/// (EX11), que é sempre com tempo. O `speed` não: o andamento da grade é o do
/// autor, e o legato, o pedal e os acentos não têm o que medir numa grade.
final _meterTypes = {
  ..._timedTypes,
  ExerciseType.playChart,
  ExerciseType.playLeadSheet,
  ExerciseType.followForm,
};

const _realtimeNote =
    'só vale com tempo real (`rhythm`, `play-score` e `play-pattern` com '
    '`mode: realtime`)';

final kPassKeys = <String, PassKey>{
  'accuracy': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 100, fallback: '90'),
    {...ExerciseType.values},
  ),
  'rounds': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 10, fallback: '1'),
    {...ExerciseType.values},
  ),
  'speed': PassKey(
    const KeyDef(ValueType.integer, min: 25, max: 200, fallback: '100'),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'time-limit': PassKey(const KeyDef(ValueType.integer, min: 1, max: 120), {
    ExerciseType.findKey,
    ExerciseType.nameNote,
    ExerciseType.countBeats,
    ExerciseType.choice,
    ExerciseType.listenNote,
    ExerciseType.listenInterval,
    ExerciseType.listenScore,
    ExerciseType.playChord,
    ExerciseType.listenChord,
    ExerciseType.listenGroove,
    ExerciseType.listenProgression,
    ExerciseType.theoryQuiz,
  }, note: 'só vale nos exercícios de pergunta'),
  // Medidores (EX08, meters.dart): medem a execução que o teclado mandou.
  // Dinâmica, equilíbrio e acentos leem só a força da tecla, e valem no modo
  // espera; o resto lê o tempo e fica para o tempo real.
  'legato': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 100),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'staccato': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 100),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'dynamics': PassKey(
    const KeyDef(ValueType.boolean, fallback: 'false'),
    _timedTypes,
  ),
  'balance': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 60),
    _timedTypes,
  ),
  'pedal': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 100),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'steadiness': PassKey(
    const KeyDef(ValueType.integer, min: 10, max: 200),
    _meterTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'swing': PassKey(
    const KeyDef(ValueType.intRange, min: 1, max: 100),
    _meterTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'accents': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 60),
    _timedTypes,
  ),
  'choruses': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 20),
    _meterTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  // EX18: a % de notas entre os alvos que saíram da fonte. Só vale com
  // `between: source` ou `free` (o leitor confere).
  'source': PassKey(const KeyDef(ValueType.integer, min: 1, max: 100), {
    ExerciseType.targetNotes,
  }, note: '`between: source` ou `free`'),
};

final _commonExerciseKeys = <String, KeyDef>{
  'id': const KeyDef(ValueType.id, required: true),
  'type': KeyDef(
    ValueType.option,
    required: true,
    values: _wires(ExerciseType.values),
  ),
  'title': const KeyDef(ValueType.text, required: true),
  'pass': const KeyDef(ValueType.passMap),
};

final _typeKeys = <ExerciseType, Map<String, KeyDef>>{
  ExerciseType.findKey: {
    'notes': _notes,
    'octave': KeyDef(
      ValueType.option,
      values: _wires(OctaveRule.values),
      fallback: 'any',
    ),
  },
  ExerciseType.playNotes: {
    'clef': _clef(),
    'key': _key,
    'notes': _notes,
    'accidentals': KeyDef(
      ValueType.option,
      values: _wires(Accidentals.values),
      fallback: 'none',
    ),
  },
  ExerciseType.nameNote: {
    'clef': _clef(),
    'key': _key,
    'notes': _notes,
    'choices': const KeyDef(
      ValueType.letterList,
      minItems: 2,
      fallback: '[C, D, E, F, G, A, B]',
    ),
  },
  ExerciseType.rhythm: {
    'time': _time,
    'figures': const KeyDef(ValueType.figureList, minItems: 1),
    'measures': const KeyDef(ValueType.integer, min: 1, max: 8, fallback: '4'),
    'abc': _abc,
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'note': const KeyDef(ValueType.note, fallback: 'C4'),
    // EX13: duas mãos e grooves. `groove` é um nome da biblioteca (no lugar de
    // `figures` e `abc`); `right` e `left` são moldes escritos (`X . | A .`);
    // `split` é a nota que separa as mãos, como no EX10.
    'hands': KeyDef(ValueType.option, values: ['one', 'two'], fallback: 'one'),
    'groove': KeyDef(ValueType.option, values: rhythmGrooveNames),
    'right': const KeyDef(ValueType.text),
    'left': const KeyDef(ValueType.text),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
  },
  ExerciseType.countBeats: {
    'time': _time,
    'figures': const KeyDef(ValueType.figureList, required: true, minItems: 1),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '8'),
  },
  ExerciseType.playScore: {
    'abc': _abc,
    'file': const KeyDef(ValueType.path, extensions: kScoreExtensions),
    'hand': KeyDef(
      ValueType.option,
      values: _wires(HandChoice.values),
      fallback: 'both',
    ),
    'mode': KeyDef(
      ValueType.option,
      values: _wires(PlayMode.values),
      fallback: 'wait',
    ),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240),
    'measures': const KeyDef(ValueType.measureRange),
    // EX05: transpor por rodada. `keys` e `cycle` não valem juntos (o leitor
    // confere); `key-start` só com um dos dois.
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
  },
  ExerciseType.choice: {
    'question': const KeyDef(ValueType.text, required: true),
    'options': const KeyDef(ValueType.stringList, required: true, minItems: 2),
    'answer': const KeyDef(ValueType.scalarText, required: true),
    'image': const KeyDef(ValueType.path, extensions: kImageExtensions),
    'abc': _abc,
  },
  ExerciseType.listenNote: {
    'notes': _notes,
    'reference': const KeyDef(ValueType.note),
    'input': KeyDef(
      ValueType.option,
      values: _wires(AnswerInput.values),
      fallback: 'keyboard',
    ),
    'octave': KeyDef(
      ValueType.option,
      values: _wires(OctaveRule.values),
      fallback: 'any',
    ),
    'key': _key,
    'choices': const KeyDef(
      ValueType.letterList,
      minItems: 2,
      fallback: '[C, D, E, F, G, A, B]',
    ),
  },
  ExerciseType.listenInterval: {
    'notes': _notes,
    'intervals': const KeyDef(
      ValueType.stringList,
      required: true,
      minItems: 2,
    ),
    'direction': KeyDef(
      ValueType.option,
      values: _wires(IntervalDirection.values),
      fallback: 'up',
    ),
    'play': KeyDef(
      ValueType.option,
      values: _wires(IntervalPlay.values),
      fallback: 'melodic',
    ),
  },
  ExerciseType.listenScore: {
    'step': const KeyDef(ValueType.scalarText, required: true),
    'change': KeyDef(
      ValueType.option,
      values: _wires(ScoreChange.values),
      fallback: 'pitch',
    ),
    'answer': KeyDef(
      ValueType.option,
      values: _wires(ScoreAnswer.values),
      fallback: 'measure',
    ),
    'count': const KeyDef(ValueType.integer, min: 1, max: 10, fallback: '5'),
    'bpm': const KeyDef(ValueType.integer, min: 40, max: 200),
  },
  ExerciseType.playChord: {
    'chords': const KeyDef(ValueType.chordsSpec, required: true, minItems: 1),
    'inversion': KeyDef(
      ValueType.optionOrList,
      values: _wires(ChordInversionChoice.values),
      fallback: 'any',
    ),
    'voicing': KeyDef(ValueType.option, values: kVoicingShapes.keys.toList()),
    'hand': KeyDef(
      ValueType.option,
      values: _wires(ChordHand.values),
      fallback: 'any',
    ),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'range': const KeyDef(ValueType.text),
    'strict': const KeyDef(ValueType.boolean, fallback: 'true'),
    'omit5': const KeyDef(ValueType.boolean, fallback: 'true'),
    'show': KeyDef(
      ValueType.option,
      values: _wires(ChordPrompt.values),
      fallback: 'symbol',
    ),
    'voice-leading': const KeyDef(ValueType.integer, min: 1, max: 12),
    // EX03: o modo com tempo. `bpm` põe o metrônomo; `beats` são os tempos
    // de cada acorde. Com `time-limit`, o validador recusa os dois.
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 200),
    'beats': const KeyDef(ValueType.integer, min: 1, max: 8, fallback: '4'),
  },
  // EX11: a grade, o molde e o juiz. O `chart` e o `pattern` são texto ou
  // mapa (`chartSpec` e `patternSpec`); o resto é como no `play-chord`.
  ExerciseType.playChart: {
    'chart': const KeyDef(ValueType.chartSpec, required: true),
    'key': _key,
    'time': _time,
    'pattern': const KeyDef(ValueType.patternSpec, required: true),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'swing': const KeyDef(ValueType.integer, min: 50, max: 75),
    'choruses': const KeyDef(ValueType.integer, min: 1, max: 20, fallback: '1'),
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'voicing': KeyDef(ValueType.option, values: kVoicingShapes.keys.toList()),
    'strict': const KeyDef(ValueType.boolean, fallback: 'true'),
    'omit5': const KeyDef(ValueType.boolean, fallback: 'true'),
    'strict-rhythm': const KeyDef(ValueType.boolean, fallback: 'false'),
    // Sem `metronome:`, liga-se com o metrônomo, e com a base ele fica
    // desligado (EX12): o padrão é lido no `mark_parser`, não aqui.
    'metronome': const KeyDef(ValueType.boolean),
    'backing': const KeyDef(ValueType.backingSpec),
    'show': KeyDef(
      ValueType.option,
      values: _wires(ChartShow.values),
      fallback: 'chords',
    ),
  },
  ExerciseType.playPattern: {
    'pattern': KeyDef(
      ValueType.option,
      required: true,
      values: _wires(PatternKind.values),
    ),
    'scale': KeyDef(
      ValueType.option,
      values: [for (final scale in ScaleKind.values) scale.wire],
      fallback: 'major',
    ),
    'chord': KeyDef(
      ValueType.option,
      values: kPatternChordQualities,
      fallback: 'M',
    ),
    'chords': KeyDef(
      ValueType.option,
      values: _wires(PatternChords.values),
      fallback: 'triads',
    ),
    'style': KeyDef(
      ValueType.option,
      values: _wires(PatternStyle.values),
      fallback: 'block',
    ),
    'figure': KeyDef(
      ValueType.option,
      values: _wires(PatternFigure.values),
      fallback: '1353',
    ),
    'order': KeyDef(
      ValueType.option,
      values: _wires(PatternOrder.values),
      fallback: '123',
    ),
    'source': KeyDef(
      ValueType.option,
      values: _wires(PatternSource.values),
      fallback: 'scale',
    ),
    // Os graus do motivo (1 a 7); a faixa é conferida pelo leitor.
    'motif': const KeyDef(ValueType.stringList, minItems: 2),
    // EX05: o tom de um padrão só, ou a lista e o ciclo (não valem juntos).
    'key': const KeyDef(ValueType.keyName, fallback: 'C'),
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
    'octaves': const KeyDef(ValueType.integer, min: 1, max: 4, fallback: '1'),
    'direction': KeyDef(
      ValueType.option,
      values: _wires(PatternDirection.values),
      fallback: 'up-down',
    ),
    'hand': KeyDef(
      ValueType.option,
      values: _wires(PatternHand.values),
      fallback: 'right',
    ),
    'fingering': const KeyDef(ValueType.boolean, fallback: 'true'),
    'articulation': KeyDef(
      ValueType.option,
      values: _wires(PatternArticulation.values),
      fallback: 'legato',
    ),
    'grouping': KeyDef(
      ValueType.option,
      values: _wires(PatternGrouping.values),
      fallback: '2',
    ),
    'mode': KeyDef(
      ValueType.option,
      values: _wires(PlayMode.values),
      fallback: 'wait',
    ),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240),
  },
  ExerciseType.listenChord: {
    'answer': KeyDef(
      ValueType.option,
      values: _wires(ChordAnswerKind.values),
      fallback: 'quality',
    ),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '10'),
    // `quality`: as qualidades dos botões, a fundamental (sorteio ou lista) e
    // a inversão e a maneira de tocar.
    'qualities': const KeyDef(ValueType.stringList, minItems: 2),
    'roots': const KeyDef(ValueType.notes),
    'inversion': KeyDef(
      ValueType.option,
      values: [
        ChordInversionChoice.root.wire,
        ChordInversionChoice.random.wire,
      ],
      fallback: 'root',
    ),
    'play': KeyDef(
      ValueType.option,
      values: _wires(ChordPlay.values),
      fallback: 'block',
    ),
    // `function`: o tom (ou `random`) e os graus que podem soar.
    'key': KeyDef(
      ValueType.option,
      values: [...kKeyNames, 'random'],
      fallback: 'C',
    ),
    'degrees': const KeyDef(
      ValueType.stringList,
      minItems: 1,
      fallback: '[I, IV, V, vi]',
    ),
  },
  // EX13: os grooves que os botões mostram (dois ou mais; o leitor confere os
  // nomes com sugestão) e as perguntas.
  ExerciseType.listenGroove: {
    'grooves': const KeyDef(ValueType.stringList, required: true, minItems: 2),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '8'),
  },
  // EX14: a frase que o app toca e o aluno repete. `source` diz de onde vêm as
  // notas; `notes`, `figures`, `leaps` e `start` não valem com `licks` (o leitor
  // confere).
  ExerciseType.echo: {
    'source': const KeyDef(ValueType.echoSource, required: true),
    'notes': const KeyDef(ValueType.integer, min: 1, max: 12, fallback: '4'),
    'figures': const KeyDef(
      ValueType.figureList,
      minItems: 1,
      fallback: '[quarter]',
    ),
    'measures': const KeyDef(ValueType.integer, min: 1, max: 2, fallback: '1'),
    'leaps': const KeyDef(ValueType.integer, min: 1, max: 7, fallback: '3'),
    'start': KeyDef(
      ValueType.option,
      values: _wires(EchoStart.values),
      fallback: 'tonic',
    ),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'swing': const KeyDef(ValueType.integer, min: 50, max: 75),
    'backing': const KeyDef(ValueType.backingSpec),
    'chart': const KeyDef(ValueType.chartSpec),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '8'),
    'octave': KeyDef(
      ValueType.option,
      values: _wires(EchoOctave.values),
      fallback: 'any',
    ),
    'transpose': KeyDef(
      ValueType.option,
      values: _wires(EchoTranspose.values),
      fallback: 'none',
    ),
    'rhythm': KeyDef(
      ValueType.option,
      values: _wires(EchoRhythm.values),
      fallback: 'loose',
    ),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'hand': const KeyDef(
      ValueType.option,
      values: ['right', 'left'],
      fallback: 'right',
    ),
  },
  // EX15: as progressões (nomes da biblioteca ou grades escritas), a resposta
  // (botões com os graus, ou o baixo no teclado), o tom (ou `random`), a base
  // (`block` ou um estilo de 4/4), o andamento e as perguntas.
  // EX16: a melodia (gerada por `step` ou do autor por `file`), os graus que o
  // acorde pode ser e onde ele troca. `mode` e `technique` são conferidos no
  // leitor (o `reharmonize` ainda não roda); o molde (`pattern`) também.
  ExerciseType.harmonize: {
    'mode': KeyDef(
      ValueType.option,
      values: _wires(HarmonizeMode.values),
      fallback: 'play',
    ),
    'technique': KeyDef(ValueType.option, values: kHarmonizeTechniques),
    'melody': const KeyDef(ValueType.melodySpec, required: true),
    'chords': const KeyDef(ValueType.stringList, minItems: 1),
    'change': KeyDef(
      ValueType.option,
      values: _wires(HarmonizeChange.values),
      fallback: 'bar',
    ),
    'pattern': const KeyDef(ValueType.text, fallback: 'block'),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 200, fallback: '70'),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'count': const KeyDef(ValueType.integer, min: 1, max: 10, fallback: '1'),
  },
  // EX18: a grade e o andamento como no `play-chart`; o alvo (`target`), onde
  // ele cai (`when`), o que se toca entre os alvos (`between`, com a fonte
  // `source`), a mão esquerda (`left`) e a faixa da direita (`register`). Sem
  // `fallback` nas que o leitor decide sozinho, para saber o que o autor pôs.
  ExerciseType.targetNotes: {
    'chart': const KeyDef(ValueType.chartSpec, required: true),
    'key': _key,
    'time': _time,
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'swing': const KeyDef(ValueType.integer, min: 50, max: 75),
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'target': KeyDef(ValueType.option, values: _wires(TargetNote.values)),
    'when': KeyDef(ValueType.option, values: _wires(TargetWhen.values)),
    'between': KeyDef(ValueType.option, values: _wires(TargetBetween.values)),
    'source': KeyDef(ValueType.option, values: _wires(TargetSource.values)),
    'left': KeyDef(
      ValueType.option,
      values: ['none', 'root', ...kVoicingShapes.keys],
    ),
    'register': const KeyDef(ValueType.text),
    'backing': const KeyDef(ValueType.backingSpec),
  },
  // EX20: a grade e o andamento como no `play-chart`, e o que o aluno faz no
  // modo (`mode`): perguntas (`where`), a entrada (`enter`) ou os sinais
  // (`cues`, com o molde `pattern`). `intro`, `ending`, `break-bars` e
  // `trade-bars` são dos modos que o leitor ainda recusa. As chaves de um modo
  // só são conferidas no leitor, que sabe o modo.
  // EX21: perguntas de teoria geradas. `topics` é a lista dos tópicos (o
  // leitor recusa o da forma, que ainda não roda); `keys` são as tônicas (sem
  // `m`; o leitor confere); `answer` vale só com tópico de nota ou acorde.
  ExerciseType.theoryQuiz: {
    'topics': KeyDef(
      ValueType.optionOrList,
      required: true,
      values: _wires(TheoryTopic.values),
    ),
    'keys': const KeyDef(ValueType.keyChoice, fallback: '[C, G, F]'),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '10'),
    'answer': KeyDef(
      ValueType.option,
      values: _wires(TheoryAnswer.values),
      fallback: 'buttons',
    ),
    // Texto, como em `listen-chord`: o `7` sem aspas é número, e vale como 7.
    'qualities': const KeyDef(ValueType.stringList, fallback: '[M, m]'),
  },
  ExerciseType.followForm: {
    'mode': KeyDef(
      ValueType.option,
      required: true,
      values: _wires(FollowMode.values),
    ),
    'chart': const KeyDef(ValueType.chartSpec, required: true),
    'key': _key,
    'time': _time,
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'swing': const KeyDef(ValueType.integer, min: 50, max: 75),
    'choruses': const KeyDef(ValueType.integer, min: 1, max: 20, fallback: '2'),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'questions': const KeyDef(
      ValueType.integer,
      min: 1,
      max: 40,
      fallback: '6',
    ),
    'answer-window': const KeyDef(
      ValueType.integer,
      min: 1,
      max: 16,
      fallback: '4',
    ),
    'enter': const KeyDef(ValueType.enterSpec),
    'cues': KeyDef(
      ValueType.optionOrList,
      values: _wires(FormSignal.values),
      minItems: 1,
      fallback: 'again, next, end',
    ),
    'pattern': const KeyDef(ValueType.patternSpec),
    'intro': KeyDef(ValueType.option, values: _wires(FormIntro.values)),
    'ending': KeyDef(ValueType.option, values: _wires(FormEnding.values)),
    'break-bars': const KeyDef(ValueType.measureRange),
    'trade-bars': const KeyDef(
      ValueType.option,
      values: ['4', '8'],
      fallback: '4',
    ),
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
    'backing': const KeyDef(ValueType.backingSpec),
  },
  // EX17: a melodia do autor (`file`, com as cifras) e o molde ou o estilo. O
  // `abc`, o tom por rodada (`keys`, `cycle`, `key-start`) e a base (`backing`)
  // estão no formato; o leitor os recusa com "ainda não roda" (ver o EX17).
  ExerciseType.playLeadSheet: {
    'file': const KeyDef(ValueType.path, extensions: kScoreExtensions),
    'abc': _abc,
    'pattern': const KeyDef(ValueType.text, fallback: 'block'),
    'style': KeyDef(ValueType.option, values: _wires(LeadStyle.values)),
    'melody': KeyDef(
      ValueType.option,
      values: _wires(LeadMelody.values),
      fallback: 'check',
    ),
    'bpm': const KeyDef(ValueType.integer, min: 30, max: 240, fallback: '80'),
    'swing': const KeyDef(ValueType.integer, min: 50, max: 75),
    'split': const KeyDef(ValueType.note, fallback: 'C4'),
    'keys': const KeyDef(ValueType.keyChoice, minItems: 1),
    'cycle': KeyDef(ValueType.option, values: _wires(KeyCycle.values)),
    'key-start': KeyDef(
      ValueType.option,
      values: _wires(KeyStart.values),
      fallback: 'written',
    ),
    'backing': const KeyDef(ValueType.backingSpec),
  },
  ExerciseType.listenProgression: {
    'answer': KeyDef(
      ValueType.option,
      values: _wires(ProgressionAnswer.values),
      fallback: 'choice',
    ),
    'progressions': const KeyDef(
      ValueType.stringList,
      required: true,
      minItems: 1,
    ),
    'key': KeyDef(
      ValueType.option,
      values: [...kKeyNames, 'random'],
      fallback: 'C',
    ),
    'style': KeyDef(
      ValueType.option,
      values: ['block', ...backingStyleNames],
      fallback: 'block',
    ),
    'bpm': const KeyDef(ValueType.integer, min: 50, max: 140, fallback: '90'),
    'count': const KeyDef(ValueType.integer, min: 1, max: 40, fallback: '8'),
  },
};

/// Chaves comuns a todo exercício (`id`, `type`, `title`, `pass`).
Map<String, KeyDef> get commonExerciseKeys => _commonExerciseKeys;

/// Chaves próprias do [type], sem as comuns.
Map<String, KeyDef> typeKeys(ExerciseType type) => _typeKeys[type]!;

/// Todas as chaves aceitas num exercício de [type].
Map<String, KeyDef> exerciseKeys(ExerciseType type) => {
  ..._commonExerciseKeys,
  ..._typeKeys[type]!,
};

import 'package:meta/meta.dart';
import 'package:zywny_music/chord_voicing.dart';
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
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'swing': PassKey(
    const KeyDef(ValueType.intRange, min: 1, max: 100),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
  'accents': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 60),
    _timedTypes,
  ),
  'choruses': PassKey(
    const KeyDef(ValueType.integer, min: 1, max: 20),
    _timedTypes,
    note: _realtimeNote,
    realtimeOnly: true,
  ),
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

import 'package:meta/meta.dart';

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
  timeSignature,

  /// `5-12` ou `5`.
  measureRange,

  /// ABC em linha (texto, em geral um bloco `|`).
  abc,

  /// O mapa `pass:`.
  passMap,
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

/// Chaves de `pass` e em que tipos cada uma vale (I00, "Critérios de aceite").
@immutable
class PassKey {
  const PassKey(this.def, this.types, {this.note});

  final KeyDef def;
  final Set<ExerciseType> types;

  /// Explicação extra para a mensagem de "não vale aqui".
  final String? note;
}

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
    {ExerciseType.rhythm, ExerciseType.playScore},
    note:
        'só vale com tempo real (`rhythm` e `play-score` com '
        '`mode: realtime`)',
  ),
  'time-limit': PassKey(const KeyDef(ValueType.integer, min: 1, max: 120), {
    ExerciseType.findKey,
    ExerciseType.nameNote,
    ExerciseType.countBeats,
    ExerciseType.choice,
  }, note: 'só vale nos exercícios de pergunta'),
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
  },
  ExerciseType.choice: {
    'question': const KeyDef(ValueType.text, required: true),
    'options': const KeyDef(ValueType.stringList, required: true, minItems: 2),
    'answer': const KeyDef(ValueType.scalarText, required: true),
    'image': const KeyDef(ValueType.path, extensions: kImageExtensions),
    'abc': _abc,
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

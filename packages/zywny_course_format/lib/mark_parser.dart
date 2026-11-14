import 'package:yaml/yaml.dart';

import 'course_issue.dart';
import 'course_model.dart';
import 'field_reader.dart';
import 'figure_rules.dart';
import 'lesson_scanner.dart';

import 'package:zywny_music/backing_styles.dart';
import 'package:zywny_music/chord.dart';
import 'package:zywny_music/chord_chart.dart';
import 'package:zywny_music/chord_degree.dart';
import 'package:zywny_music/chord_voicing.dart';
import 'package:zywny_music/comping_patterns.dart';
import 'package:zywny_music/fingering.dart';
import 'package:zywny_music/note_name.dart';
import 'package:zywny_music/progressions.dart';
import 'package:zywny_music/rhythm_grooves.dart';
import 'package:zywny_music/scale.dart';

import 'suggest.dart';
import 'vocabulary.dart';

/// Lê uma marca ` ```zywny-… ` e devolve o bloco da lição, ou `null` se a
/// marca tem erro (já registrado em [issues]).
LessonBlock? parseMark(
  MarkSegment mark,
  FileIssues issues,
  Set<String> existing,
) {
  final reader = FieldReader(issues, existing);
  if (mark.name != kExerciseMark && !kContentMarkKeys.containsKey(mark.name)) {
    final hint = suggestFor(mark.name, kMarkNames);
    issues.error(
      mark.line,
      'marca desconhecida `zywny-${mark.name}`'
      '${hint != null ? ' — você quis dizer `zywny-$hint`?' : ''} '
      '(marcas: ${kMarkNames.map((n) => 'zywny-$n').join(', ')}).',
    );
    return null;
  }
  final map = reader.parseMap(mark.body, mark.bodyLine, blockLine: mark.line);
  if (map == null) return null;
  final where = 'na marca `zywny-${mark.name}`';

  if (mark.name == kExerciseMark) {
    final spec = _parseExercise(map, mark, reader, issues);
    return spec == null ? null : ExerciseMark(spec, mark.line);
  }

  final fields = reader.read(
    map,
    kContentMarkKeys[mark.name]!,
    FieldBlock(firstLine: mark.bodyLine, blockLine: mark.line, where: where),
  );
  if (fields.failed) return null;
  final before = issues.errorCount;
  final block = switch (mark.name) {
    'score' => _score(fields, mark, issues),
    'keyboard' => _keyboard(fields, mark, issues),
    'chart' => _chart(fields, mark, issues),
    'audio' => AudioMark(
      line: mark.line,
      file: fields.get<String>('file')!,
      caption: fields.get<String>('caption'),
    ),
    _ => VideoMark(
      line: mark.line,
      link: fields.get<String>('link')!,
      caption: fields.get<String>('caption'),
    ),
  };
  return issues.errorCount > before ? null : block;
}

/// `abc` xor `file`; devolve a fonte ou `null` (erro registrado).
ScoreSource? _scoreSource(Fields f, FileIssues issues, {String? missing}) {
  final abc = f.get<String>('abc');
  final file = f.get<String>('file');
  if (abc != null && file != null) {
    issues.error(f.lineOf('file'), 'use só um: `abc` ou `file`, não os dois.');
    return null;
  }
  if (abc != null) return AbcSource(abc);
  if (file != null) return FileSource(file);
  issues.error(f.blockLine, missing ?? 'informe `abc` ou `file`.');
  return null;
}

/// `keys:` do `play-score` (EX05): `all`, `random` ou a lista de tons. Um valor
/// inválido já deu erro no leitor (e a chave some do `Fields`).
KeyChoice? _keyChoice(Fields f) {
  final value = f.get<Object>('keys');
  if (value is List<Object>) return FixedKeys(value.cast<String>());
  return switch (value) {
    'all' => const AllKeys(),
    'random' => const RandomKeys(),
    _ => null,
  };
}

/// Os tons do `play-score` (EX05) não se misturam: `keys` ou `cycle`, nunca os
/// dois. O `key-start` pede um dos dois, e com `keys: random` não há começo
/// para ele.
bool _keyRules(Fields f, FileIssues issues) {
  var ok = true;
  if (f.has('keys') && f.has('cycle')) {
    issues.error(
      f.lineOf('cycle'),
      '`keys` e `cycle` não valem juntos: escolha uma lista de tons ou um ciclo.',
    );
    ok = false;
  }
  if (f.has('key-start')) {
    if (!f.has('keys') && !f.has('cycle')) {
      issues.error(
        f.lineOf('key-start'),
        '`key-start` só vale com `keys` ou `cycle`.',
      );
      ok = false;
    } else if (f.get<Object>('keys') == 'random') {
      issues.error(
        f.lineOf('key-start'),
        '`key-start` não vale com `keys: random`: o sorteio não tem começo.',
      );
      ok = false;
    }
  }
  return ok;
}

/// As regras do `play-score` da leitura pela música (T18): o `.mxl`, o
/// `transpose` e o `student` (a parte do aluno). Devolve `false` se algo não
/// vale; o erro já foi dado em [issues].
bool _playScoreT18Rules(Fields f, ScoreSource source, FileIssues issues) {
  final cumulative = f.has('practice');
  final sequence = f.get<String>('hand') == 'sequence';
  // Cada regra confere o que lhe cabe, sem parar na primeira.
  final mxl = _mxlRules(f, cumulative, issues);
  final transpose = _transposeRules(f, issues);
  final student =
      !f.has('student') ||
      _studentRules(f, source, issues, cumulative || sequence);
  return mxl && transpose && student;
}

/// Um `.mxl` não vale com `keys`, `cycle` nem `practice: cumulative`.
bool _mxlRules(Fields f, bool cumulative, FileIssues issues) {
  final file = f.get<String>('file');
  if (file == null || !file.toLowerCase().endsWith('.mxl')) return true;
  if (!f.has('keys') && !f.has('cycle') && !cumulative) return true;
  issues.error(
    f.lineOf('file'),
    'um `.mxl` não vale com `keys`, `cycle` nem `practice: cumulative`: '
    'use o `.musicxml` descompactado.',
  );
  return false;
}

/// `transpose` não vale junto com `keys` nem `cycle`.
bool _transposeRules(Fields f, FileIssues issues) {
  if (!f.has('transpose') || (!f.has('keys') && !f.has('cycle'))) return true;
  issues.error(
    f.lineOf('transpose'),
    '`transpose` não vale junto com `keys` nem `cycle`: escolha um jeito de '
    'mudar o tom.',
  );
  return false;
}

/// `student` (a parte do aluno): só com `file`, sem `practice: cumulative` nem
/// `hand: sequence` ([practiceOrSequence]), e sem id repetido.
bool _studentRules(
  Fields f,
  ScoreSource source,
  FileIssues issues,
  bool practiceOrSequence,
) {
  var ok = true;
  if (source is! FileSource) {
    issues.error(
      f.lineOf('student'),
      '`student` só vale com `file`: os ids das notas vêm do arquivo '
      'MusicXML.',
    );
    ok = false;
  }
  if (practiceOrSequence) {
    issues.error(
      f.lineOf('student'),
      '`student` não vale com `practice: cumulative` nem `hand: sequence`.',
    );
    ok = false;
  }
  final unique = _studentIdsUnique(f, issues);
  return ok && unique;
}

bool _studentIdsUnique(Fields f, FileIssues issues) {
  var ok = true;
  final seen = <String>{};
  for (final item in f.get<List<Object>>('student') ?? const <Object>[]) {
    final ids = '$item'.split(RegExp(r'\s+')).where((id) => id.isNotEmpty);
    for (final id in ids) {
      if (!seen.add(id)) {
        issues.error(
          f.lineOf('student'),
          'o id `$id` aparece duas vezes em `student`.',
        );
        ok = false;
      }
    }
  }
  return ok;
}

ScoreMark? _score(Fields f, MarkSegment mark, FileIssues issues) {
  final source = _scoreSource(f, issues);
  if (source == null) return null;
  _headerKeys(f, source, ['clef', 'key', 'time'], issues);
  return ScoreMark(
    line: mark.line,
    source: source,
    clef: _enumOf(Clef.values, f.get<String>('clef')) ?? Clef.treble,
    key: f.get<String>('key'),
    time: f.get<String>('time'),
    highlight: f.get<List<Object>>('highlight')?.cast<Pitch>() ?? const [],
    caption: f.get<String>('caption'),
  );
}

/// `clef`/`key`/`time` só fazem sentido num `abc` de corpo: o ABC completo
/// (`X:`) e o `.musicxml` já trazem o cabeçalho.
void _headerKeys(
  Fields f,
  ScoreSource source,
  List<String> keys,
  FileIssues issues,
) {
  final given = keys.where(f.has).toList();
  if (given.isEmpty) return;
  final names = given.map((k) => '`$k`').join(', ');
  if (source is AbcSource && source.isComplete) {
    issues.error(
      f.lineOf(given.first),
      'um `abc` com `X:` já traz o cabeçalho: tire $names.',
    );
  } else if (source is FileSource) {
    issues.error(
      f.lineOf(given.first),
      '$names só valem com `abc`; o arquivo `.musicxml` traz o cabeçalho.',
    );
  }
}

KeyboardMark? _keyboard(Fields f, MarkSegment mark, FileIssues issues) {
  final from = f.get<Pitch>('from') ?? Pitch.parse('C3');
  final to = f.get<Pitch>('to') ?? Pitch.parse('C5');
  final marked = f.get<List<Object>>('mark')?.cast<Pitch>() ?? const [];
  if (from.midi > to.midi) {
    issues.error(
      f.lineOf('from'),
      '`from` ($from) precisa ser mais grave que `to` ($to).',
    );
    return null;
  }
  for (final pitch in marked) {
    if (pitch.midi < from.midi || pitch.midi > to.midi) {
      issues.error(
        f.lineOf('mark'),
        'a nota `$pitch` em `mark` está fora da faixa $from-$to do teclado.',
      );
      return null;
    }
  }
  return KeyboardMark(
    line: mark.line,
    from: from,
    to: to,
    mark: marked,
    names: f.get<bool>('names') ?? false,
    caption: f.get<String>('caption'),
  );
}

/// `zywny-chart` (EX09): ou o texto da grade (`chart`), ou uma progressão da
/// biblioteca (`progression`), nunca os dois. O texto passa pelo leitor de
/// grades aqui, para o erro sair na lição; o erro traz a coluna na linha.
ChartMark? _chart(Fields f, MarkSegment mark, FileIssues issues) {
  final text = f.get<String>('chart');
  final progression = f.get<String>('progression');
  if (text == null && progression == null) {
    issues.error(
      f.blockLine,
      'informe `chart` (a grade escrita) ou `progression` (um nome da '
      'biblioteca).',
    );
    return null;
  }
  if (text != null && progression != null) {
    issues.error(
      f.lineOf('progression'),
      'use só um: `chart` ou `progression`, não os dois.',
    );
    return null;
  }
  if (progression == null && f.has('bars')) {
    issues.error(
      f.lineOf('bars'),
      '`bars` só vale com `progression`: a grade escrita já tem os seus '
      'compassos.',
    );
    return null;
  }
  final key = f.get<String>('key') ?? 'C';
  final time = f.get<String>('time') ?? '4/4';
  if (!_gradeReads(f, issues)) return null;
  return ChartMark(
    line: mark.line,
    key: key,
    time: time,
    chart: text,
    progression: progression,
    bars: f.get<int>('bars'),
    degrees: f.get<bool>('degrees') ?? false,
    caption: f.get<String>('caption'),
  );
}

/// Confere a grade da marca: o nome da progressão, ou o texto lido pelo leitor
/// do EX09 (cada erro sai com a coluna). Falso se há erro.
bool _gradeReads(Fields f, FileIssues issues) => _gradeOf(
  issues: issues,
  reading: (
    text: f.get<String>('chart'),
    progression: f.get<String>('progression'),
    key: f.get<String>('key') ?? 'C',
    time: f.get<String>('time') ?? '4/4',
    textLine: f.lineOf('chart'),
    progressionLine: f.lineOf('progression'),
  ),
);

/// A grade de uma marca ou de um exercício: o nome da progressão da biblioteca,
/// ou o texto lido pelo leitor do EX09 (cada erro sai com a coluna).
bool _gradeOf({
  required ({
    String? text,
    String? progression,
    String key,
    String time,
    int textLine,
    int progressionLine,
  })
  reading,
  required FileIssues issues,
}) {
  final text = reading.text;
  final progression = reading.progression;
  final key = reading.key;
  final time = reading.time;
  final textLine = reading.textLine;
  final progressionLine = reading.progressionLine;
  if (progression != null) {
    if (progressionNamed(progression) != null) return true;
    final hint = suggestFor(progression, [
      for (final p in kProgressions) p.name,
    ]);
    issues.error(
      progressionLine,
      'não há a progressão `$progression` na biblioteca'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    return false;
  }
  final grade = ChordChart.parse(
    text!,
    key: KeySpec.parse(key)!,
    time: time,
    error: (message, col) =>
        issues.error(textLine, 'na grade (coluna $col): $message'),
  );
  return grade != null;
}

T? _enumOf<T extends WireEnum>(List<T> values, String? wire) =>
    wire == null ? null : values.firstWhere((v) => v.wire == wire);

ExerciseSpec? _parseExercise(
  YamlMap map,
  MarkSegment mark,
  FieldReader reader,
  FileIssues issues,
) {
  final type = _exerciseTypeOf(map, mark, issues);
  if (type == null) return null;
  final f = reader.read(
    map,
    exerciseKeys(type),
    FieldBlock(
      firstLine: mark.bodyLine,
      blockLine: mark.line,
      where: 'no exercício `${type.wire}`',
    ),
  );
  final before = issues.errorCount;
  // `pass` é conferido mesmo se outra chave falhou: o autor vê tudo de uma vez.
  _checkPass(type, f.get<Fields>('pass'), issues, (
    realtime: _isRealtime(type, f),
    hasTempo: _hasTempo(type, f),
  ));
  if (f.failed) return null;
  final spec = _buildExercise(type, f, mark, issues);
  return issues.errorCount > before ? null : spec;
}

/// O tipo do exercício (a chave `type`); `null` se falta ou não existe, com o
/// erro já dado.
ExerciseType? _exerciseTypeOf(
  YamlMap map,
  MarkSegment mark,
  FileIssues issues,
) {
  final typeNode = map.nodes['type'];
  final wires = ExerciseType.values.map((t) => t.wire).toList();
  final typeName = typeNode?.value;
  final type = typeName is String
      ? ExerciseType.values.where((t) => t.wire == typeName).firstOrNull
      : null;
  if (type != null) return type;
  final line = typeNode == null
      ? mark.line
      : mark.bodyLine + typeNode.span.start.line;
  if (typeNode == null) {
    issues.error(
      line,
      'falta a chave obrigatória `type` na marca `zywny-exercise` '
      '(tipos: ${wires.join(', ')}).',
    );
  } else {
    final hint = typeName is String ? suggestFor(typeName, wires) : null;
    issues.error(
      line,
      'tipo de exercício desconhecido `$typeName`'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
      '(tipos: ${wires.join(', ')}).',
    );
  }
  return null;
}

/// Os tipos que são sempre em tempo real, e o `play-score`/`play-pattern` com
/// `mode: realtime`: o `pass` deles aceita `realtime`.
bool _isRealtime(ExerciseType type, Fields f) =>
    type == ExerciseType.rhythm ||
    type == ExerciseType.playChart ||
    type == ExerciseType.playLeadSheet ||
    ((type == ExerciseType.playScore || type == ExerciseType.playPattern) &&
        f.get<String>('mode') == 'realtime');

/// Os tipos com andamento: o tempo real (`_isRealtime`) e o `play-score`/
/// `play-pattern` com `mode: hold` (ND03). No `hold` a duração de cada nota no
/// relógio depende do `speed`; os medidores (legato, pedal…) seguem só no
/// tempo real, por isso `_checkPass` separa as duas perguntas.
bool _hasTempo(ExerciseType type, Fields f) =>
    _isRealtime(type, f) ||
    ((type == ExerciseType.playScore || type == ExerciseType.playPattern) &&
        f.get<String>('mode') == 'hold');

PassCriteria _pass(Fields? pass) => PassCriteria(
  accuracy: pass?.get<int>('accuracy') ?? 90,
  rounds: pass?.get<int>('rounds') ?? 1,
  speed: pass?.get<int>('speed') ?? 100,
  timeLimit: pass?.get<int>('time-limit'),
  legato: pass?.get<int>('legato'),
  staccato: pass?.get<int>('staccato'),
  dynamics: pass?.get<bool>('dynamics') ?? false,
  balance: pass?.get<int>('balance'),
  pedal: pass?.get<int>('pedal'),
  steadiness: pass?.get<int>('steadiness'),
  swing: pass?.get<(int, int)>('swing'),
  accents: pass?.get<int>('accents'),
  choruses: pass?.get<int>('choruses'),
  source: pass?.get<int>('source'),
  tempoLadder: _ladderOf(pass?.get<Fields>('tempo-ladder')),
);

/// O `tempo-ladder` lido (EX22). Com uma chave faltando, o erro já foi
/// registrado pelo leitor, e a especificação sai de qualquer jeito (com
/// `null`): o `pass` sem escada não é usado.
TempoLadder? _ladderOf(Fields? f) {
  final from = f?.get<int>('from');
  final to = f?.get<int>('to');
  final step = f?.get<int>('step');
  final back = f?.get<int>('back');
  if (from == null || to == null || step == null || back == null) return null;
  return TempoLadder(from: from, to: to, step: step, back: back);
}

/// `tempo-ladder` (EX22) troca o `speed` (o andamento é o da escada), e a meta
/// (`to`) não fica abaixo do começo (`from`).
void _checkLadder(Fields pass, FileIssues issues) {
  if (!pass.has('tempo-ladder')) return;
  final line = pass.lineOf('tempo-ladder');
  if (pass.has('speed')) {
    issues.error(
      pass.lineOf('speed'),
      '`speed` não vale junto com `tempo-ladder`: a escada já põe o andamento '
      '(tire `speed`).',
    );
  }
  final ladder = pass.get<Fields>('tempo-ladder');
  final from = ladder?.get<int>('from');
  final to = ladder?.get<int>('to');
  if (from != null && to != null && to < from) {
    issues.error(
      line,
      '`tempo-ladder`: a meta (`to: $to`) fica abaixo do começo (`from: $from`).',
    );
  }
}

/// `pass` só pode ter as chaves que valem no tipo (e `speed` só com andamento:
/// tempo real ou `hold`; os medidores só com tempo real).
void _checkPass(
  ExerciseType type,
  Fields? pass,
  FileIssues issues,
  ({bool realtime, bool hasTempo}) tempo,
) {
  if (pass == null) return;
  _checkLadder(pass, issues);
  for (final key in pass.values.keys) {
    final rule = kPassKeys[key]!;
    if (!rule.types.contains(type)) {
      issues.error(
        pass.lineOf(key),
        '`$key` não vale em `${type.wire}`: ${rule.note ?? 'ver a '
                'especificação'}.',
      );
    } else if (rule.realtimeOnly &&
        !(key == 'speed' ? tempo.hasTempo : tempo.realtime)) {
      issues.error(
        pass.lineOf(key),
        key == 'speed'
            ? 'o modo espera não tem andamento: tire `speed` ou use '
                  '`mode: realtime` ou `mode: hold`.'
            : 'o modo espera não mede o tempo tocado: tire `$key` ou use '
                  '`mode: realtime`.',
      );
    }
  }
}

/// Os naturais de [range] que o `only` aceita (todos, sem `only`).
List<Pitch> _pool(NoteRange range, OnlyOn? only) => [
  for (final pitch in range.naturals)
    if (only == null || (only == OnlyOn.lines) == pitch.onLine) pitch,
];

/// As regras da leitura de notas de um exercício: quantas notas vêm por padrão,
/// se só valem as naturais (com as [letters] escolhidas) e de qual chave lê.
class _NotesRule {
  const _NotesRule({
    required this.defaultCount,
    this.naturalsOnly = false,
    this.letters,
    this.key = 'notes',
  });

  final int defaultCount;
  final bool naturalsOnly;
  final List<String>? letters;
  final String key;
}

/// `notes` como [NotesSpec]; confere faixa, `only` e quantidade. [letters]
/// e [naturalsOnly] valem para o `name-note`. [key] lê outra chave com a
/// mesma sintaxe (o `roots` do `listen-chord`).
NotesSpec? _notes(Fields f, FileIssues issues, _NotesRule rule) {
  final raw = f.values[rule.key];
  final line = f.lineOf(rule.key);
  if (raw is List) {
    return _fixedNotes(raw.cast<Pitch>(), line, rule, issues);
  }
  final random = raw as Fields;
  if (random.failed) return null;
  return _randomNotes(random, line, rule, issues);
}

/// Notas escritas: cada uma tem de caber no tipo (`naturalsOnly`, `letters`).
NotesSpec? _fixedNotes(
  List<Pitch> notes,
  int line,
  _NotesRule rule,
  FileIssues issues,
) {
  final letters = rule.letters;
  for (final pitch in notes) {
    if (rule.naturalsOnly && !pitch.isNatural) {
      issues.error(
        line,
        '`$pitch` tem sustenido ou bemol: neste tipo só '
        'valem as notas naturais.',
      );
      return null;
    }
    if (letters != null && !letters.contains(pitch.step)) {
      issues.error(
        line,
        '`$pitch` não tem botão em `choices` '
        '(${letters.join(', ')}): a pergunta ficaria sem resposta.',
      );
      return null;
    }
  }
  return FixedNotes(notes);
}

/// O sorteio (`random`, `only`, `count`): a faixa precisa de duas notas, e
/// com `only` ter pelo menos duas; as notas sorteadas têm de caber em
/// `letters`. [line] é a linha de `notes`.
NotesSpec? _randomNotes(
  Fields random,
  int line,
  _NotesRule rule,
  FileIssues issues,
) {
  final range = _randomRange(random, issues);
  if (range == null) return null;
  final only = _enumOf(OnlyOn.values, random.get<String>('only'));
  if (range.to.midi == range.from.midi) {
    issues.error(
      random.lineOf('random'),
      'a faixa $range tem uma nota só: o sorteio '
      'precisa de pelo menos duas.',
    );
    return null;
  }
  final pool = _pool(range, only);
  if (only != null && pool.length < 2) {
    issues.error(
      random.lineOf('only'),
      'a faixa $range tem ${pool.length} '
      '${only == OnlyOn.lines ? 'nota em linha' : 'nota em espaço'}: '
      'com `only: ${only.wire}` o sorteio precisa de pelo menos duas.',
    );
    return null;
  }
  final letters = rule.letters;
  if (letters != null) {
    final missing = {for (final p in pool) p.step}
        .where((l) => !letters.contains(l));
    if (missing.isNotEmpty) {
      issues.error(
        line,
        'a faixa $range sorteia ${missing.join(', ')}, '
        '${missing.length == 1 ? 'que não tem botão' : 'que não têm botão'} '
        'em `choices` (${letters.join(', ')}).',
      );
      return null;
    }
  }
  return RandomNotes(
    range: range,
    count: random.get<int>('count') ?? rule.defaultCount,
    only: only,
  );
}

/// A faixa do sorteio (`random: C4-G5`): `null`, com o erro, se não é uma faixa.
NoteRange? _randomRange(Fields random, FileIssues issues) {
  final text = random.get<String>('random')!;
  final range = NoteRange.tryParse(text);
  if (range != null) return range;
  issues.error(
    random.lineOf('random'),
    '`$text` não é uma faixa de notas: escreva da mais grave para a mais '
    'aguda, como C4-G5.',
  );
  return null;
}

/// Cada figura precisa caber em um compasso de [time].
bool _figuresFit(
  List<Figure> figures,
  String time,
  Fields f,
  FileIssues issues,
) {
  final length = measureEighths(time);
  for (final figure in figures) {
    if (figure.eighths > length) {
      issues.error(
        f.lineOf('figures'),
        'a figura `${figure.wire}` não cabe em um compasso $time.',
      );
      return false;
    }
  }
  if (!figuresTileMeasure(figures, time)) {
    issues.error(
      f.lineOf('figures'),
      figures.every((x) => x.rest)
          ? '`figures` só tem pausas: o aluno não teria o que tocar.'
          : 'estas `figures` não preenchem um compasso $time sem sobra '
                '(colcheias saem em pares) e com ao menos uma nota: junte '
                'uma figura que complete o compasso.',
    );
    return false;
  }
  return true;
}

/// O cabeçalho de um exercício: o id, o título, a linha, e o bloco `pass:`.
typedef _Head = ({String id, String title, int line, Fields? pass});

ExerciseSpec? _buildExercise(
  ExerciseType type,
  Fields f,
  MarkSegment mark,
  FileIssues issues,
) {
  final head = (
    id: f.get<String>('id')!,
    title: f.get<String>('title')!,
    line: mark.line,
    pass: f.get<Fields>('pass'),
  );
  return switch (type) {
    ExerciseType.findKey => _findKeySpec(f, head, issues),
    ExerciseType.playNotes => _playNotesSpec(f, head, issues),
    ExerciseType.nameNote => _nameNoteSpec(f, head, issues),
    ExerciseType.rhythm => _rhythm(f, head, issues),
    ExerciseType.countBeats => _countBeatsSpec(f, head, issues),
    ExerciseType.playScore => _playScoreSpec(f, head, issues),
    ExerciseType.choice => _choiceSpec(f, head, issues),
    ExerciseType.listenNote => _listenNoteSpec(f, head, issues),
    ExerciseType.listenInterval => _listenIntervalSpec(f, head, issues),
    ExerciseType.listenScore => _listenScoreSpec(f, head, issues),
    ExerciseType.playChord => _playChord(f, head, issues),
    ExerciseType.playPattern => _playPattern(f, head, issues),
    ExerciseType.playChart => _playChart(f, head, issues),
    ExerciseType.listenChord => _listenChord(f, head, issues),
    ExerciseType.listenGroove => _listenGroove(f, head, issues),
    ExerciseType.echo => _echo(f, head, issues),
    ExerciseType.listenProgression => _listenProgression(f, head, issues),
    ExerciseType.harmonize => _harmonize(f, head, issues),
    ExerciseType.playLeadSheet => _playLeadSheet(f, head, issues),
    ExerciseType.targetNotes => _targetNotes(f, head, issues),
    ExerciseType.followForm => _followForm(f, head, issues),
    ExerciseType.theoryQuiz => _theoryQuiz(f, head, issues),
  };
}

ExerciseSpec? _findKeySpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final notes = _notes(f, issues, _NotesRule(defaultCount: 10));
  if (notes == null) return null;
  return FindKeySpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    notes: notes,
    octave:
        _enumOf(OctaveRule.values, f.get<String>('octave')) ?? OctaveRule.any,
  );
}

ExerciseSpec? _playNotesSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final notes = _notes(f, issues, _NotesRule(defaultCount: 12));
  if (notes == null) return null;
  final accidentals =
      _enumOf(Accidentals.values, f.get<String>('accidentals')) ??
      Accidentals.none;
  if (f.has('accidentals') && notes is FixedNotes) {
    issues.error(
      f.lineOf('accidentals'),
      '`accidentals` só vale com sorteio (`notes: {random: …}`); numa '
      'lista fixa escreva a nota com # ou b, como F#4.',
    );
    return null;
  }
  return PlayNotesSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    clef: _enumOf(Clef.values, f.get<String>('clef')) ?? Clef.treble,
    key: f.get<String>('key'),
    notes: notes,
    accidentals: accidentals,
  );
}

ExerciseSpec? _nameNoteSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final choices =
      f.get<List<Object>>('choices')?.cast<String>() ??
      const ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  final notes = _notes(
    f,
    issues,
    _NotesRule(defaultCount: 12, naturalsOnly: true, letters: choices),
  );
  if (notes == null) return null;
  return NameNoteSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    clef: _enumOf(Clef.values, f.get<String>('clef')) ?? Clef.treble,
    key: f.get<String>('key'),
    notes: notes,
    choices: choices,
  );
}

ExerciseSpec? _countBeatsSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final time = f.get<String>('time') ?? '4/4';
  final figures = f.get<List<Object>>('figures')!.cast<Figure>();
  if (!_figuresFit(figures, time, f, issues)) return null;
  return CountBeatsSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    time: time,
    figures: figures,
    count: f.get<int>('count') ?? 8,
  );
}

ExerciseSpec? _playScoreSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final mode = _enumOf(PlayMode.values, f.get<String>('mode')) ?? PlayMode.wait;
  final source = _scoreSource(f, issues);
  if (source == null) return null;
  final keys = _keyChoice(f);
  final cycle = _enumOf(KeyCycle.values, f.get<String>('cycle'));
  if (!_keyRules(f, issues)) return null;
  if (!_playScoreT18Rules(f, source, issues)) return null;
  final curtain = f.get<bool>('curtain') ?? false;
  if (curtain && mode != PlayMode.realtime) {
    issues.error(
      f.lineOf('curtain'),
      '`curtain: true` só vale com `mode: realtime` (no modo espera a '
      'partitura não anda sozinha).',
    );
    return null;
  }
  return PlayScoreSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    source: source,
    hand: _enumOf(HandChoice.values, f.get<String>('hand')) ?? HandChoice.both,
    mode: mode,
    bpm: f.get<int>('bpm'),
    measures: f.get<MeasureRange>('measures'),
    keys: keys,
    cycle: cycle,
    keyStart:
        _enumOf(KeyStart.values, f.get<String>('key-start')) ??
        KeyStart.written,
    practice: _enumOf(PracticeChoice.values, f.get<String>('practice')),
    curtain: curtain,
    transpose: f.get<int>('transpose') ?? 0,
    student: [
      for (final item in f.get<List<Object>>('student') ?? const <Object>[])
        [
          for (final id in '$item'.split(RegExp(r'\s+')))
            if (id.isNotEmpty) id,
        ],
    ],
  );
}

ExerciseSpec? _choiceSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final options = f.get<List<Object>>('options')!.cast<String>();
  final answer = f.get<String>('answer')!;
  var ok = true;
  if (options.toSet().length != options.length) {
    issues.error(f.lineOf('options'), '`options` repete uma opção.');
    ok = false;
  }
  final index = options.indexOf(answer);
  if (index < 0) {
    issues.error(
      f.lineOf('answer'),
      '`answer` (`$answer`) precisa ser igual a uma das `options`: '
      '${options.map((o) => '`$o`').join(', ')}.',
    );
    ok = false;
  }
  if (f.has('image') && f.has('abc')) {
    issues.error(f.lineOf('abc'), 'use só um: `image` ou `abc`.');
    ok = false;
  }
  if (!ok) return null;
  return ChoiceSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    question: f.get<String>('question')!,
    options: options,
    answer: index,
    image: f.get<String>('image'),
    abc: f.get<String>('abc'),
  );
}

ExerciseSpec? _listenNoteSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final input =
      _enumOf(AnswerInput.values, f.get<String>('input')) ??
      AnswerInput.keyboard;
  final buttons = input == AnswerInput.buttons;
  var ok = true;
  for (final k in buttons ? ['octave', 'key'] : ['choices']) {
    if (f.has(k)) {
      issues.error(
        f.lineOf(k),
        '`$k` só vale com `input: ${buttons ? 'keyboard' : 'buttons'}`.',
      );
      ok = false;
    }
  }
  if (!ok) return null;
  final choices =
      f.get<List<Object>>('choices')?.cast<String>() ??
      const ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  final notes = buttons
      ? _notes(
          f,
          issues,
          _NotesRule(defaultCount: 10, naturalsOnly: true, letters: choices),
        )
      : _notes(f, issues, _NotesRule(defaultCount: 10));
  if (notes == null) return null;
  return ListenNoteSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    notes: notes,
    reference: f.get<Pitch>('reference'),
    input: input,
    octave:
        _enumOf(OctaveRule.values, f.get<String>('octave')) ?? OctaveRule.any,
    choices: choices,
    key: f.get<String>('key'),
  );
}

ExerciseSpec? _listenIntervalSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final notes = _notes(f, issues, _NotesRule(defaultCount: 10));
  if (notes == null) return null;
  final intervals = <IntervalName>[];
  for (final text in f.get<List<Object>>('intervals')!.cast<String>()) {
    final interval = IntervalName.values
        .where((i) => i.wire == text)
        .firstOrNull;
    if (interval == null) {
      issues.error(
        f.lineOf('intervals'),
        '`$text` não é um intervalo; use: '
        '${IntervalName.values.map((i) => i.wire).join(', ')}.',
      );
      return null;
    }
    if (intervals.contains(interval)) {
      issues.error(f.lineOf('intervals'), '`intervals` repete um intervalo.');
      return null;
    }
    intervals.add(interval);
  }
  return ListenIntervalSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    notes: notes,
    intervals: intervals,
    direction:
        _enumOf(IntervalDirection.values, f.get<String>('direction')) ??
        IntervalDirection.up,
    play:
        _enumOf(IntervalPlay.values, f.get<String>('play')) ??
        IntervalPlay.melodic,
  );
}

ExerciseSpec? _listenScoreSpec(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final step = f.get<String>('step')!;
  final match = _stepPattern.firstMatch(step);
  if (match == null) {
    issues.error(
      f.lineOf('step'),
      '`$step` não é um passo do treino de leitura: use de `1a` a `100d`.',
    );
    return null;
  }
  final answer =
      _enumOf(ScoreAnswer.values, f.get<String>('answer')) ??
      ScoreAnswer.measure;
  if (answer == ScoreAnswer.dictation && f.has('change')) {
    issues.error(
      f.lineOf('change'),
      '`change` não vale com `answer: dictation`: a frase soa como está escrita.',
    );
    return null;
  }
  final change =
      _enumOf(ScoreChange.values, f.get<String>('change')) ?? ScoreChange.pitch;
  if (change == ScoreChange.accidental && int.parse(match.group(1)!) < 11) {
    issues.error(
      f.lineOf('change'),
      '`change: accidental` pede um passo com armadura, do `11a` em diante.',
    );
    return null;
  }
  return ListenScoreSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    step: step,
    change: change,
    answer: answer,
    count: f.get<int>('count') ?? 5,
    bpm: f.get<int>('bpm'),
  );
}

/// `play-chord` (EX02): as cifras, a inversão, o molde, a mão e a faixa. Os
/// erros de cifra, de grau, de inversão e de molde saem já na leitura, com a
/// linha da chave ou do item.
/// `play-pattern` (EX06): o padrão, o tom (`key:`, ou `keys:` e `cycle:` como
/// no `play-score`), a mão e as variações. Chave que só vale com outro padrão é
/// erro; `fingering: true` num padrão sem dedilhado só avisa.
PlayPatternSpec? _playPattern(Fields f, _Head head, FileIssues issues) {
  final pattern = _enumOf(PatternKind.values, f.get<String>('pattern'))!;
  var ok = _patternRules(f, pattern, issues);
  final motif = _motifOf(f, issues);
  if (!motif.ok) ok = false;
  if (!_chordRange(f, issues)) ok = false;
  if (!ok) return null;

  _warnFingering(f, issues, pattern);
  return _playPatternSpec(f, head, pattern, motif.motif);
}

/// O `play-pattern` já lido e sem erro: o padrão, a escala e os tons, a mão,
/// as variações e o andamento (os valores vêm de [f]; as regras já passaram).
PlayPatternSpec _playPatternSpec(
  Fields f,
  _Head head,
  PatternKind pattern,
  List<int> motif,
) {
  return PlayPatternSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    pattern: pattern,
    scale: _scaleOf(f.get<String>('scale')),
    chord: f.get<String>('chord') ?? 'M',
    chords: _choice(f, 'chords', PatternChords.values, PatternChords.triads),
    style: _choice(f, 'style', PatternStyle.values, PatternStyle.block),
    figure: _choice(
      f,
      'figure',
      PatternFigure.values,
      PatternFigure.figure1353,
    ),
    order: _choice(f, 'order', PatternOrder.values, PatternOrder.order123),
    source: _choice(f, 'source', PatternSource.values, PatternSource.scale),
    motif: motif,
    key: f.get<String>('key') ?? 'C',
    keys: _keyChoice(f),
    cycle: _enumOf(KeyCycle.values, f.get<String>('cycle')),
    keyStart: _choice(f, 'key-start', KeyStart.values, KeyStart.written),
    octaves: f.get<int>('octaves') ?? 1,
    direction: _choice(
      f,
      'direction',
      PatternDirection.values,
      PatternDirection.upDown,
    ),
    hand: _patternHandOf(f),
    handSequence: f.get<String>('hand') == 'sequence',
    fingering: f.get<bool>('fingering') ?? true,
    articulation: _choice(
      f,
      'articulation',
      PatternArticulation.values,
      PatternArticulation.legato,
    ),
    grouping: _choice(
      f,
      'grouping',
      PatternGrouping.values,
      PatternGrouping.two,
    ),
    mode: _choice(f, 'mode', PlayMode.values, PlayMode.wait),
    bpm: f.get<int>('bpm'),
  );
}

/// A mão do molde. `sequence` (EX22) não é um PatternHand: a mão do molde é as
/// duas, e a rodada troca a mão em cada passo.
PatternHand _patternHandOf(Fields f) => f.get<String>('hand') == 'sequence'
    ? PatternHand.both
    : _choice(f, 'hand', PatternHand.values, PatternHand.right);

/// O valor escrito em [key] (uma palavra de [values]), ou [fallback] se a
/// chave não existe ou não casa.
T _choice<T extends WireEnum>(
  Fields f,
  String key,
  List<T> values,
  T fallback,
) => _enumOf(values, f.get<String>(key)) ?? fallback;

/// As regras de tom e de chaves de um `play-pattern`: a chave `key` com
/// `keys`, as que só valem com alguns padrões e o `motif` do `sequence`.
bool _patternRules(Fields f, PatternKind pattern, FileIssues issues) {
  var ok = _keyRules(f, issues);
  // `key:` é o tom de um padrão só, e o ponto de partida do `cycle:` (EX05);
  // com `keys:`, a lista já traz os tons.
  if (f.has('key') && f.has('keys')) {
    issues.error(
      f.lineOf('key'),
      '`key` não vale com `keys`: a lista já traz os tons.',
    );
    ok = false;
  }
  for (final MapEntry(key: key, value: kinds) in _onlyWithPattern.entries) {
    if (f.has(key) && !kinds.contains(pattern)) {
      issues.error(
        f.lineOf(key),
        '`$key` só vale com `pattern: ${kinds.map((k) => k.wire).join(' ou ')}`.',
      );
      ok = false;
    }
  }
  if (pattern == PatternKind.sequence && !f.has('motif')) {
    issues.error(
      f.blockLine,
      '`pattern: sequence` pede `motif`, com os graus do motivo (como [1, 2, 3, 1]).',
    );
    ok = false;
  }
  return ok;
}

/// O `motif` (os graus) do `play-pattern`: `motif` (de 1 a 7). Erro se algum
/// grau está fora disso; [ok] diz se todos presta.
({List<int> motif, bool ok}) _motifOf(Fields f, FileIssues issues) {
  var ok = true;

  final motif = <int>[];
  final wires =
      f.get<List<Object>>('motif')?.cast<String>() ?? const <String>[];
  for (final wire in wires) {
    final degree = int.tryParse(wire);
    if (degree == null || degree < 1 || degree > 7) {
      issues.error(
        f.lineOf('motif'),
        '`motif` tem graus de 1 a 7; recebi `$wire`.',
      );
      ok = false;
    } else {
      motif.add(degree);
    }
  }
  return (motif: motif, ok: ok);
}

/// `chord: 3-5-7-9` (o jazz) é de uma oitava só: a descida é 7 5 3 1. `false`
/// (com o erro) se passa disso.
bool _chordRange(Fields f, FileIssues issues) {
  var ok = true;
  // O arpejo de 3-5-7-9 (o jazz) é de uma oitava só: a descida é 7 5 3 1.
  if (f.get<String>('chord') == '3-5-7-9' && (f.get<int>('octaves') ?? 1) > 1) {
    issues.error(
      f.lineOf('octaves'),
      '`chord: 3-5-7-9` vai só até uma oitava (a descida é 7 5 3 1).',
    );
    ok = false;
  }
  return ok;
}

/// O aviso do dedilhado que o padrão não traz (ver `fingering:`).
void _warnFingering(Fields f, FileIssues issues, PatternKind pattern) {
  final scale = _scaleOf(f.get<String>('scale'));
  final keys = _keyChoice(f);
  final cycle = _enumOf(KeyCycle.values, f.get<String>('cycle'));
  final key = f.get<String>('key') ?? 'C';
  final octaves = f.get<int>('octaves') ?? 1;
  if (f.has('fingering') && (f.get<bool>('fingering') ?? true)) {
    final gap = f.get<String>('hand') == 'contrary'
        ? 'sem dedilhado na mão contrária: o livro não traz. '
              'Use `fingering: false` para calar o aviso.'
        : _fingeringGap(pattern, (
            scale: scale,
            chord: f.get<String>('chord') ?? 'M',
            key: key,
            keys: keys,
            cycle: cycle,
            octaves: octaves,
          ));
    if (gap != null) issues.warning(f.lineOf('fingering'), gap);
  }
}

/// As chaves de `play-pattern` que só valem com alguns padrões (o erro diz
/// quais).
const _onlyWithPattern = <String, Set<PatternKind>>{
  'figure': {PatternKind.brokenChord},
  'chord': {PatternKind.arpeggio, PatternKind.brokenChord},
  'chords': {PatternKind.diatonicChords},
  'style': {PatternKind.diatonicChords},
  'order': {PatternKind.threeNote},
  'source': {PatternKind.threeNote},
  'motif': {PatternKind.sequence},
};

/// A escala de `scale:` (o padrão é a maior).
ScaleKind _scaleOf(String? wire) => ScaleKind.values.firstWhere(
  (scale) => scale.wire == wire,
  orElse: () => ScaleKind.major,
);

/// O tom de um dedilhado: a escala, a fundamental do acorde, o tom, a
/// escolha de tons (`keys:`), o ciclo e as oitavas.
typedef _FingerKey = ({
  ScaleKind scale,
  String chord,
  String key,
  KeyChoice? keys,
  KeyCycle? cycle,
  int octaves,
});

/// O aviso de `fingering: true` num padrão sem dedilhado, ou `null` quando o
/// livro traz. Com vários tons (`keys:`, `cycle:`), basta um tom fora da tabela
/// para avisar.
String? _fingeringGap(PatternKind pattern, _FingerKey key) {
  final scale = key.scale;
  final chord = key.chord;
  final keyName = key.key;
  final keys = key.keys;
  final cycle = key.cycle;
  final octaves = key.octaves;
  const none =
      'sem dedilhado para este padrão: o livro não traz. '
      'Use `fingering: false` para calar o aviso.';
  switch (pattern) {
    case PatternKind.fiveFinger:
      return null;
    case PatternKind.arpeggio when chord != 'M' && chord != 'm':
      // Só a tríade maior e a menor têm dedilhado (Pike, arpejos de duas oitavas).
      return none;
    case PatternKind.scale || PatternKind.arpeggio:
      if (cycle != null || keys != null) {
        final names = switch (keys) {
          FixedKeys(keys: final list) => list,
          _ => const <String>[],
        };
        final covered =
            names.isNotEmpty &&
            names.every((name) => _hasTable(pattern, scale, name, octaves));
        return covered ? null : none;
      }
      return _hasTable(pattern, scale, keyName, octaves) ? null : none;
    default:
      return none;
  }
}

/// Se a tônica [name] (`C`, `Bb`, `Am`) tem dedilhado para o padrão, na mão
/// direita.
bool _hasTable(PatternKind pattern, ScaleKind scale, String name, int octaves) {
  final key = KeySpec.parse(name);
  if (key == null) return false;
  if (pattern == PatternKind.arpeggio) {
    return arpeggioFingering(key, right: true, octaves: octaves) != null;
  }
  return scaleFingering(scale, key, right: true, octaves: octaves) != null;
}

PlayChordSpec? _playChord(Fields f, _Head head, FileIssues issues) {
  final chords = _chords(f, issues);
  if (chords == null) return null;
  final samples = chords.samples;
  final inversions = _chordInversions(f);
  var ok = _checkThirdInversion(f, issues, inversions, samples);
  if (!_checkVoicing(f, issues, samples)) ok = false;
  final range = _chordRangeOf(f, issues);
  if (!range.ok) ok = false;
  if (!_checkBeatsAndBpm(f, issues)) ok = false;
  if (!ok) return null;
  final bpm = f.get<int>('bpm');
  return PlayChordSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    chords: chords.spec,
    inversions: inversions,
    voicing: f.get<String>('voicing'),
    hand: _chordHand(f),
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    range: range.range,
    bpm: bpm,
    beats: f.get<int>('beats') ?? 4,
    strict: f.get<bool>('strict') ?? true,
    omit5: f.get<bool>('omit5') ?? true,
    prompt:
        _enumOf(ChordPrompt.values, f.get<String>('show')) ??
        ChordPrompt.symbol,
    voiceLeading: f.get<int>('voice-leading'),
  );
}

/// As inversões que o exercício sorteia (`inversion:`, uma ou uma lista).
List<ChordInversionChoice> _chordInversions(Fields f) {
  final rawInversion = f.values['inversion'];
  return rawInversion is List
      ? [
          for (final wire in rawInversion.cast<String>())
            _enumOf(ChordInversionChoice.values, wire)!,
        ]
      : [
          _enumOf(
            ChordInversionChoice.values,
            (rawInversion as String?) ?? 'any',
          )!,
        ];
}

/// A mão do acorde (`hand:`); sem ela, qualquer uma.
ChordHand _chordHand(Fields f) =>
    _enumOf(ChordHand.values, f.get<String>('hand')) ?? ChordHand.any;

/// A 3ª inversão pede uma cifra de sétima. `false` (com o erro) se alguma
/// cifra é tríade.
bool _checkThirdInversion(
  Fields f,
  FileIssues issues,
  List<ChordInversionChoice> inversions,
  List<ChordSymbol> samples,
) {
  if (inversions.contains(ChordInversionChoice.third) &&
      samples.any((sample) => sample.seventh == null)) {
    issues.error(
      f.lineOf('inversion'),
      'tríade não tem 3ª inversão: `third` pede uma cifra de sétima.',
    );
    return false;
  }
  return true;
}

/// O molde (`voicing:`): não pode vir com `inversion:`, tem que caber em todas
/// as cifras e, com `hand: left`, avisa o que não cabe na esquerda. `false`
/// (com o erro) se algo não presta.
bool _checkVoicing(Fields f, FileIssues issues, List<ChordSymbol> samples) {
  final voicing = f.get<String>('voicing');
  if (voicing == null) return true;
  var ok = true;
  final shape = kVoicingShapes[voicing]!;
  final inversions = _chordInversions(f);
  if (inversions.any((i) => i != ChordInversionChoice.any)) {
    issues.error(
      f.lineOf('voicing'),
      'o molde já decide a ordem das notas; tire `inversion`.',
    );
    ok = false;
  }
  for (final sample in samples) {
    try {
      buildVoicing(
        sample,
        shape: shape,
        bounds: VoicingBounds(lowest: 36, highest: 96),
      );
    } on ArgumentError {
      issues.error(
        f.lineOf('voicing'),
        '`$voicing` não cabe em `${sample.label(ChordNotation.american)}`.',
      );
      ok = false;
      break;
    }
  }
  if (_chordHand(f) == ChordHand.left &&
      const {'so-what', 'upper-triad', 'block'}.contains(voicing)) {
    issues.warning(
      f.lineOf('hand'),
      '`$voicing` pede as duas mãos; com `hand: left` o acorde inteiro '
      'fica na esquerda.',
    );
  }
  return ok;
}

/// A faixa do exercício (`range:`, da mais grave para a mais aguda).
({NoteRange? range, bool ok}) _chordRangeOf(Fields f, FileIssues issues) {
  final rangeText = f.get<String>('range');
  if (rangeText == null) return (range: null, ok: true);
  final range = NoteRange.tryParse(rangeText);
  if (range == null) {
    issues.error(
      f.lineOf('range'),
      '`$rangeText` não é uma faixa de notas: escreva da mais grave para a '
      'mais aguda, como C3-C6.',
    );
    return (range: null, ok: false);
  }
  return (range: range, ok: true);
}

/// EX03: o modo com tempo. O `bpm` marca cada pergunta, então não vale junto
/// com o `time-limit` (que também marca o fim de cada pergunta). `false` (com
/// o erro) se algo não presta.
bool _checkBeatsAndBpm(Fields f, FileIssues issues) {
  var ok = true;
  final bpm = f.get<int>('bpm');
  if (bpm == null && f.has('beats')) {
    issues.error(
      f.lineOf('beats'),
      '`beats` só vale com `bpm`: o tempo de cada acorde vem do andamento.',
    );
    ok = false;
  }
  if (bpm != null && f.get<Fields>('pass')?.get<int>('time-limit') != null) {
    issues.error(
      f.lineOf('bpm'),
      '`bpm` e `time-limit` não valem juntos: o metrônomo já marca o fim de '
      'cada pergunta.',
    );
    ok = false;
  }
  return ok;
}

/// `play-chart` (EX11): a grade (texto, ou a progressão da biblioteca com
/// `chart: {progression, key, bars}`), o molde (um nome da biblioteca, ou o
/// mapa `pattern: {grid, left, right}`), o andamento e o juiz. Um molde de
/// outro compasso que a grade é erro; `swing` pede colcheias no molde.
/// O que o `play-chart` já conferiu e o spec leva.
typedef _ChartParts = ({
  String? text,
  String? progression,
  int? bars,
  String key,
  String time,
  CompingPattern pattern,
  BackingSpec? backing,
});

PlayChartSpec? _playChart(Fields f, _Head head, FileIssues issues) {
  final grade = _chartGrade(f, issues);
  if (grade == null) return null;
  var ok = grade.ok;
  final pattern = _patternOf(f, issues);
  if (pattern == null) ok = false;
  if (!_chartRules(f, pattern, grade.time, issues)) ok = false;
  final backing = pattern == null
      ? null
      : _backingOf(f, backingStyleFor(pattern), grade.time, issues);
  if (f.has('backing') && backing == null) ok = false;
  if (!ok || pattern == null) return null;
  return _chartSpec(f, head, (
    text: grade.text,
    progression: grade.progression,
    bars: grade.bars,
    key: grade.key,
    time: grade.time,
    pattern: pattern,
    backing: backing,
  ));
}

/// A grade de `play-chart` e `target-notes`: o texto, ou a progressão da
/// biblioteca (com o tom dentro de `chart`), e o compasso. [ok] é falso se algo
/// não vale; `null` se não há `chart` (e nada mais se confere).
typedef _ChartGrade = ({
  bool ok,
  String time,
  String? text,
  String? progression,
  int? bars,
  String key,
});

_ChartGrade? _chartGrade(Fields f, FileIssues issues) {
  var ok = _keyRules(f, issues);
  final time = f.get<String>('time') ?? '4/4';
  final chart = f.values['chart'];
  final map = chart is Fields ? chart : null;
  // Com a progressão, o tom vai dentro do `chart`; em texto, é o `key:`.
  if (map != null && f.has('key')) {
    issues.error(
      f.lineOf('key'),
      '`key` fica dentro de `chart` quando a grade vem da biblioteca: '
      '`chart: {progression: …, key: …}`.',
    );
    ok = false;
  }
  final key = map != null
      ? map.get<String>('key') ?? 'C'
      : f.get<String>('key') ?? 'C';
  if (chart == null) return null;
  final text = map == null ? chart as String : null;
  final progression = map?.get<String>('progression');
  if (!_gradeOf(
    issues: issues,
    reading: (
      text: text,
      progression: progression,
      key: key,
      time: time,
      textLine: f.lineOf('chart'),
      progressionLine: map?.lineOf('progression') ?? f.lineOf('chart'),
    ),
  )) {
    ok = false;
  }
  return (
    ok: ok,
    time: time,
    text: text,
    progression: progression,
    bars: map?.get<int>('bars'),
    key: key,
  );
}

/// O compasso do molde (tem de ser o da grade), o `swing` (pede colcheias no
/// molde) e o `beats` (não vale no `play-chart`).
bool _chartRules(
  Fields f,
  CompingPattern? pattern,
  String time,
  FileIssues issues,
) {
  var ok = true;
  if (pattern?.time != null && pattern!.time != time) {
    issues.error(
      f.lineOf('pattern'),
      'o molde `${pattern.name}` é de ${pattern.time}, e a grade é de $time.',
    );
    ok = false;
  }
  final swing = f.get<int>('swing');
  if (pattern != null &&
      swing != null &&
      swing != 50 &&
      !const {6, 8, 16}.contains(pattern.grid)) {
    issues.error(
      f.lineOf('swing'),
      '`swing` pede colcheias no molde, e o `grid` ${pattern.grid} não tem '
      '(use grid 6, 8 ou 16, ou tire `swing`).',
    );
    ok = false;
  }
  if (f.get<int>('bpm') == null && f.has('beats')) {
    issues.error(f.lineOf('beats'), '`beats` não vale no `play-chart`.');
    ok = false;
  }
  return ok;
}

PlayChartSpec _chartSpec(Fields f, _Head head, _ChartParts p) {
  return PlayChartSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    chartText: p.text,
    progression: p.progression,
    progressionBars: p.bars,
    key: p.key,
    time: p.time,
    pattern: p.pattern,
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing'),
    choruses: f.get<int>('choruses') ?? 1,
    voicing: f.get<String>('voicing'),
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    strict: f.get<bool>('strict') ?? true,
    omit5: f.get<bool>('omit5') ?? true,
    strictRhythm: f.get<bool>('strict-rhythm') ?? false,
    // Com a base, o metrônomo começa desligado (EX12).
    metronome: f.get<bool>('metronome') ?? p.backing == null,
    show: _choice(f, 'show', ChartShow.values, ChartShow.chords),
    keys: _keyChoice(f),
    cycle: _enumOf(KeyCycle.values, f.get<String>('cycle')),
    keyStart: _choice(f, 'key-start', KeyStart.values, KeyStart.written),
    backing: p.backing,
  );
}

/// `target-notes` (EX18): a grade (texto, ou a progressão da biblioteca, como no
/// `play-chart`), a nota-alvo (`target`), onde ela cai (`when`), o que se toca
/// entre os alvos (`between`, e a fonte delas, `source`), a mão esquerda (`left`)
/// e a faixa da direita (`register`). O que o juiz confere (se a nota é a 3ª do
/// acorde, se o trecho cabe na fonte) é do app. `null` com erro (o erro já saiu).
TargetNotesSpec? _targetNotes(Fields f, _Head head, FileIssues issues) {
  final grade = _chartGrade(f, issues);
  if (grade == null) return null;
  final between = _choice(
    f,
    'between',
    TargetBetween.values,
    TargetBetween.free,
  );
  final betweenOk = _targetRules(f, between, grade.time, issues);
  final range = _registerRange(f, issues);
  final backing = _backingOf(
    f,
    backingStyleNamed('swing')!,
    grade.time,
    issues,
  );
  final backingOk = !f.has('backing') || backing != null;
  if (!grade.ok || !betweenOk || range == null || !backingOk) return null;
  return _targetSpec(f, head, (
    grade: grade,
    between: between,
    range: range,
    backing: backing,
  ));
}

/// O que `target-notes` já conferiu e o spec leva.
typedef _TargetParts = ({
  _ChartGrade grade,
  TargetBetween between,
  NoteRange range,
  BackingSpec? backing,
});

TargetNotesSpec _targetSpec(Fields f, _Head head, _TargetParts p) {
  return TargetNotesSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    chartText: p.grade.text,
    progression: p.grade.progression,
    progressionBars: p.grade.bars,
    key: p.grade.key,
    time: p.grade.time,
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing'),
    target: _choice(f, 'target', TargetNote.values, TargetNote.three),
    when: _choice(f, 'when', TargetWhen.values, TargetWhen.change),
    between: p.between,
    source: _choice(f, 'source', TargetSource.values, TargetSource.keyScale),
    left: f.get<String>('left') ?? 'none',
    registerFrom: p.range.from,
    registerTo: p.range.to,
    split: _splitOf(f),
    keys: _keyChoice(f),
    cycle: _enumOf(KeyCycle.values, f.get<String>('cycle')),
    keyStart: _choice(f, 'key-start', KeyStart.values, KeyStart.written),
    backing: p.backing,
  );
}

/// A faixa da mão direita (`register`, da mais grave à mais aguda). Ela não
/// pode começar abaixo do `split`. `null`, com o erro dado, se não vale.
NoteRange? _registerRange(Fields f, FileIssues issues) {
  final range = NoteRange.tryParse(f.get<String>('register') ?? 'C4-C6');
  if (range == null) {
    issues.error(
      f.lineOf('register'),
      '`register` é uma faixa de notas, da mais grave para a mais aguda '
      '(como C4-C6).',
    );
    return null;
  }
  final split = _splitOf(f);
  if (range.from.midi < split.midi) {
    issues.error(
      f.lineOf('register'),
      '`register` começa abaixo do `split` (${split.midi}): a mão direita '
      'começa nele, e a faixa da direita não pode descer até a esquerda.',
    );
    return null;
  }
  return range;
}

/// O `split` (a nota que divide as mãos); padrão dó4.
Pitch _splitOf(Fields f) => f.get<Pitch>('split') ?? Pitch.parse('C4');

/// As regras de combinação do `target-notes` (EX18): o `source` (da chave e do
/// `pass`) só com `between: source` ou `free`, e o `half-bar` só em compasso de
/// tempo par (os tempos 1 e 3 são o meio do compasso). Falso se algo está errado.
bool _targetRules(
  Fields f,
  TargetBetween between,
  String time,
  FileIssues issues,
) {
  final pass = f.get<Fields>('pass');
  var ok = true;
  final fromFree =
      between == TargetBetween.source || between == TargetBetween.free;
  if (f.has('source') && !fromFree) {
    issues.error(
      f.lineOf('source'),
      '`source` só vale com `between: source` ou `free`: a fonte é das notas '
      'entre os alvos.',
    );
    ok = false;
  }
  if (pass != null && pass.has('source') && !fromFree) {
    issues.error(
      pass.lineOf('source'),
      '`source` no `pass` só vale com `between: source` ou `free`.',
    );
    ok = false;
  }
  if (f.get<String>('when') == 'half-bar' && _beatsOfTime(time).isOdd) {
    issues.error(
      f.lineOf('when'),
      '`when: half-bar` pede um compasso de tempo par (4/4, 2/4, 6/8, 12/8 '
      'ou C), e a grade é de $time.',
    );
    ok = false;
  }
  return ok;
}

/// Os tempos de um compasso de [time], pela conta do `ChordChart` (6/8 leva 2).
int _beatsOfTime(String time) {
  if (time == 'C') return 4;
  final parts = time.split('/');
  final top = int.parse(parts[0]);
  return parts[1] == '8' && top % 3 == 0 ? top ~/ 3 : top;
}

/// `follow-form` (EX20): a grade (como no `play-chart`), o modo e as chaves de
/// cada modo. `intro-outro`, `break` e `trading` estão no formato, mas o leitor
/// os recusa com "ainda não roda" (o passe deles vem depois). `null` com erro (o
/// erro já saiu).
FollowFormSpec? _followForm(Fields f, _Head head, FileIssues issues) {
  var ok = _keyRules(f, issues);
  final time = f.get<String>('time') ?? '4/4';
  final chart = _followChartOf(f, issues);
  if (chart == null) return null;
  if (!chart.ok) ok = false;
  final mode = _enumOf(FollowMode.values, f.get<String>('mode'));
  if (mode == null) return null;
  if (_unrunnableMode(f, mode, issues)) return null;
  final grade = _gradeQuietly((
    text: chart.text,
    progression: chart.progression,
    progressionBars: chart.bars,
    key: chart.key,
    time: time,
  ));
  if (!_followModeRules(f, mode, issues)) ok = false;
  final enter = mode == FollowMode.enter
      ? _followEnter(f, time, grade, issues)
      : null;
  final cues = mode == FollowMode.cues ? _followCues(f, grade, issues) : null;
  final pattern = mode == FollowMode.cues
      ? _cuesPattern(f, time, issues)
      : null;
  if (mode == FollowMode.enter && enter == null) ok = false;
  if (mode == FollowMode.cues && (cues == null || pattern == null)) ok = false;
  final backing = _backingOf(f, backingStyleNamed('swing')!, time, issues);
  if (f.has('backing') && backing == null) ok = false;
  if (!ok) return null;
  return _followSpec(f, head, (
    chart: chart,
    mode: mode,
    time: time,
    enter: enter,
    cues: cues,
    pattern: pattern,
    backing: backing,
  ));
}

/// O que `follow-form` já conferiu e o spec leva.
typedef _FollowParts = ({
  ({String? text, String? progression, String key, int? bars, bool ok}) chart,
  FollowMode mode,
  String time,
  FollowEnter? enter,
  List<FormSignal>? cues,
  CompingPattern? pattern,
  BackingSpec? backing,
});

FollowFormSpec _followSpec(Fields f, _Head head, _FollowParts p) {
  return FollowFormSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    mode: p.mode,
    chartText: p.chart.text,
    progression: p.chart.progression,
    progressionBars: p.chart.bars,
    key: p.chart.key,
    time: p.time,
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing'),
    choruses: f.get<int>('choruses') ?? 2,
    split: _splitOf(f),
    questions: f.get<int>('questions') ?? 6,
    answerWindow: f.get<int>('answer-window') ?? 4,
    cues: p.cues ?? const [],
    enter: p.enter,
    pattern: p.pattern,
    keys: _keyChoice(f),
    cycle: _enumOf(KeyCycle.values, f.get<String>('cycle')),
    keyStart: _choice(f, 'key-start', KeyStart.values, KeyStart.written),
    backing: p.backing,
  );
}

/// A grade do `follow-form` (`chart:`, o texto ou a progressão da biblioteca):
/// o tom (dentro do `chart`, com a progressão; em texto, é o `key:`) e os
/// compassos. `null` se não há `chart:`; `ok` diz se ela se lê.
({String? text, String? progression, String key, int? bars, bool ok})?
_followChartOf(Fields f, FileIssues issues) {
  var ok = true;
  final time = f.get<String>('time') ?? '4/4';
  final chart = f.values['chart'];
  final map = chart is Fields ? chart : null;
  // Com a progressão, o tom vai dentro do `chart`; em texto, é o `key:`.
  if (map != null && f.has('key')) {
    issues.error(
      f.lineOf('key'),
      '`key` fica dentro de `chart` quando a grade vem da biblioteca: '
      '`chart: {progression: …, key: …}`.',
    );
    ok = false;
  }
  final key = map != null
      ? map.get<String>('key') ?? 'C'
      : f.get<String>('key') ?? 'C';
  if (chart == null) return null;
  final text = map == null ? chart as String : null;
  final progression = map?.get<String>('progression');
  if (!_gradeOf(
    issues: issues,
    reading: (
      text: text,
      progression: progression,
      key: key,
      time: time,
      textLine: f.lineOf('chart'),
      progressionLine: map?.lineOf('progression') ?? f.lineOf('chart'),
    ),
  )) {
    ok = false;
  }
  return (
    text: text,
    progression: progression,
    key: key,
    bars: map?.get<int>('bars'),
    ok: ok,
  );
}

/// Os modos do `follow-form` que estão no formato mas ainda não rodam (o passe
/// deles vem depois): erro com o que roda, e `true`.
bool _unrunnableMode(Fields f, FollowMode mode, FileIssues issues) {
  if (mode != FollowMode.introOutro &&
      mode != FollowMode.breakBars &&
      mode != FollowMode.trading) {
    return false;
  }
  issues.error(
    f.lineOf('mode'),
    '`mode: ${mode.wire}` ainda não roda: o `follow-form` roda `where`, '
    '`enter` e `cues` (os outros modos estão no formato, sem o passe).',
  );
  return true;
}

/// A grade de um `follow-form` sem erros de texto (para os limites dos modos):
/// `null` se ela não se lê, o que já saiu como erro.
ChordChart? _gradeQuietly(
  ({
    String? text,
    String? progression,
    int? progressionBars,
    String key,
    String time,
  })
  reading,
) {
  final text = reading.text;
  final progression = reading.progression;
  final progressionBars = reading.progressionBars;
  final key = reading.key;
  final time = reading.time;
  final parsedKey = KeySpec.parse(key);
  if (parsedKey == null) return null;
  if (progression != null) {
    if (progressionNamed(progression) == null) return null;
    return ChordChart.fromProgression(
      progression,
      key: parsedKey,
      time: time,
      bars: progressionBars,
    );
  }
  return ChordChart.parse(text!, key: parsedKey, time: time);
}

/// As chaves que valem só em alguns modos de `follow-form` (EX20). Cada uma
/// fora do seu modo é erro, com o modo que ela pede. Falso se algo está errado.
bool _followModeRules(Fields f, FollowMode mode, FileIssues issues) {
  const modeOf = {
    'questions': FollowMode.where,
    'answer-window': FollowMode.where,
    'enter': FollowMode.enter,
    'cues': FollowMode.cues,
    'pattern': FollowMode.cues,
    'intro': FollowMode.introOutro,
    'ending': FollowMode.introOutro,
    'break-bars': FollowMode.breakBars,
    'trade-bars': FollowMode.trading,
  };
  var ok = true;
  for (final entry in modeOf.entries) {
    if (f.has(entry.key) && entry.value != mode) {
      issues.error(
        f.lineOf(entry.key),
        '`${entry.key}` só vale com `mode: ${entry.value.wire}`, e este '
        'exercício é `mode: ${mode.wire}`.',
      );
      ok = false;
    }
  }
  if (f.has('choruses') && mode == FollowMode.cues) {
    issues.error(
      f.lineOf('choruses'),
      '`choruses` não vale com `mode: cues`: a forma é a que os sinais pedem.',
    );
    ok = false;
  }
  return ok;
}

/// O `enter:` do modo `enter`: os compassos (`bars`, contando do 1) ou a seção,
/// e o molde do que se toca ali. `null` com erro.
FollowEnter? _followEnter(
  Fields f,
  String time,
  ChordChart? grade,
  FileIssues issues,
) {
  final raw = f.values['enter'];
  if (raw is! Fields) {
    issues.error(
      f.lineOf('enter'),
      '`mode: enter` pede `enter`, com `bars` (ou `section`) e `pattern`.',
    );
    return null;
  }
  final bars = raw.get<MeasureRange>('bars');
  final section = raw.get<String>('section');
  if ((bars == null) == (section == null)) {
    issues.error(
      raw.lineOf('bars'),
      '`enter` pede `bars` ou `section`, um dos dois.',
    );
    return null;
  }
  final patternName = raw.get<String>('pattern')!;
  final pattern = compingPatternNamed(patternName);
  if (pattern == null) {
    final hint = suggestFor(patternName, compingPatternNames);
    issues.error(
      raw.lineOf('pattern'),
      'não há o padrão `$patternName` na biblioteca'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    return null;
  }
  if (pattern.time != null && pattern.time != time) {
    issues.error(
      raw.lineOf('pattern'),
      'o molde `${pattern.name}` é de ${pattern.time}, e a grade é de $time.',
    );
    return null;
  }
  if (grade != null) {
    final problem = _enterProblem(grade, bars, section);
    if (problem != null) {
      issues.error(raw.lineOf(bars == null ? 'section' : 'bars'), problem);
      return null;
    }
  }
  return FollowEnter(pattern: pattern, bars: bars, section: section);
}

/// Por que `bars` ou `section` do `enter` não cabem na grade, ou `null`.
String? _enterProblem(ChordChart grade, MeasureRange? bars, String? section) {
  if (bars != null) {
    if (bars.to > grade.bars.length) {
      return 'o `enter` pede os compassos $bars, e a grade tem '
          '${grade.bars.length}.';
    }
    return null;
  }
  if (!grade.sections.any((s) => s.label == section)) {
    return 'não há a seção `$section` na grade.';
  }
  return null;
}

/// O `pattern:` do `cues`: o molde da biblioteca, como no `play-chart`. Sem a
/// chave, é erro (o `cues` precisa do que o aluno toca). `null` com erro.
CompingPattern? _cuesPattern(Fields f, String time, FileIssues issues) {
  if (!f.has('pattern')) {
    issues.error(
      f.lineOf('mode'),
      '`mode: cues` pede `pattern`, o molde que o aluno segue (como '
      '`pattern: straight-beat`).',
    );
    return null;
  }
  final pattern = _patternOf(f, issues);
  if (pattern != null && pattern.time != null && pattern.time != time) {
    issues.error(
      f.lineOf('pattern'),
      'o molde `${pattern.name}` é de ${pattern.time}, e a grade é de $time.',
    );
    return null;
  }
  return pattern;
}

/// Os sinais do `cues`, em ordem; o padrão são `again`, `next` e `end`. Confere
/// o que cada um pede da grade: `bridge` a seção `B`, `next`, `back-to-A` e
/// `bridge` mais de uma seção, e `tag` quatro compassos. Sem `end` nem `tag`, a
/// forma não acabaria. `null` com erro.
List<FormSignal>? _followCues(Fields f, ChordChart? grade, FileIssues issues) {
  final raw = f.values['cues'];
  if (raw == null) {
    return const [FormSignal.again, FormSignal.next, FormSignal.end];
  }
  final names = raw is String ? [raw] : [for (final v in raw as List) '$v'];
  final signals = [for (final name in names) _enumOf(FormSignal.values, name)!];
  if (!signals.contains(FormSignal.end) && !signals.contains(FormSignal.tag)) {
    issues.error(
      f.lineOf('cues'),
      '`cues` precisa de `end` ou `tag`, para a forma acabar.',
    );
    return null;
  }
  if (grade == null) return signals;
  var ok = true;
  final sections = grade.sections.length;
  for (final signal in signals) {
    final problem = switch (signal) {
      FormSignal.bridge when !grade.sections.any((s) => s.label == 'B') =>
        '`bridge` vai para a seção `B:`, e a grade não tem.',
      FormSignal.next || FormSignal.backToA || FormSignal.bridge
          when sections < 2 =>
        '`${signal.wire}` pede uma grade com mais de uma seção (`A:`, `B:`).',
      FormSignal.tag when grade.bars.length < 4 =>
        '`tag` volta quatro compassos antes do fim, e a grade tem menos.',
      _ => null,
    };
    if (problem != null) {
      issues.error(f.lineOf('cues'), problem);
      ok = false;
    }
  }
  return ok ? signals : null;
}

/// `backing:` do `play-chart` (EX12) e do `target-notes` (EX18): `drums` (só a
/// bateria, sem baixo) ou o mapa `{style, drums, bass, volume, intro}`. Sem
/// `style:`, é [defaultStyle] (o do molde, no `play-chart`). `null` sem
/// `backing:` ou com erro (o erro já saiu).
BackingSpec? _backingOf(
  Fields f,
  BackingStyle defaultStyle,
  String time,
  FileIssues issues,
) {
  final raw = f.values['backing'];
  if (raw == null) return null;
  final map = raw is Fields ? raw : null;
  final style = _backingStyleOf(map, defaultStyle, issues);
  if (style == null) return null;
  if (style.time != time) {
    issues.error(
      f.lineOf('backing'),
      'o estilo `${style.name}` é de ${style.time}, e a grade é de $time.',
    );
    return null;
  }
  // Só com o texto `drums` o baixo é desligado; com o mapa, é a 5ª.
  final bass = BackingBass.values.firstWhere(
    (b) =>
        b.wire ==
        (map?.get<String>('bass') ?? (map == null ? 'none' : 'root-fifth')),
  );
  if (bass == BackingBass.walking && time == '3/4') {
    issues.warning(
      map?.lineOf('bass') ?? f.lineOf('backing'),
      'walking em 3/4 soa estranho; use `root`.',
    );
  }
  return BackingSpec(
    style: style,
    drums: map?.get<bool>('drums') ?? true,
    bass: bass,
    volume: map?.get<int>('volume') ?? 70,
    intro: map?.get<int>('intro') ?? 1,
  );
}

/// O estilo da base: o `style:` do mapa (um nome da tabela), ou o padrão do
/// compasso. `null`, com o erro dado, se o nome não está na tabela.
BackingStyle? _backingStyleOf(
  Fields? map,
  BackingStyle defaultStyle,
  FileIssues issues,
) {
  final name = map?.get<String>('style');
  if (name == null) return defaultStyle;
  final named = backingStyleNamed(name);
  if (named != null) return named;
  final hint = suggestFor(name, backingStyleNames);
  issues.error(
    map!.lineOf('style'),
    'não há o estilo `$name` na tabela de estilos'
    '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
  );
  return null;
}

/// O `pattern:` do `play-chart`: o nome de um padrão da biblioteca, ou o molde
/// escrito. `null` se algo está errado (o erro já saiu).
CompingPattern? _patternOf(Fields f, FileIssues issues) {
  final raw = f.values['pattern'];
  if (raw == 'any') return kAnyCompingPattern;
  if (raw is String) {
    final pattern = compingPatternNamed(raw);
    if (pattern != null) return pattern;
    final hint = suggestFor(raw, compingPatternNames);
    issues.error(
      f.lineOf('pattern'),
      'não há o padrão `$raw` na biblioteca'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    return null;
  }
  final map = raw as Fields?;
  if (map == null) return null;
  return _writtenPattern(map, issues);
}

/// O molde escrito (`grid`, `left`, `right`): as duas mãos com o mesmo número
/// de compassos.
CompingPattern? _writtenPattern(Fields map, FileIssues issues) {
  final grid = map.get<int>('grid');
  if (grid == null) return null;
  if (!const {2, 3, 4, 6, 8, 12, 16}.contains(grid)) {
    issues.error(
      map.lineOf('grid'),
      '`grid` aceita 2, 3, 4, 6, 8, 12 ou 16 partes por compasso (recebi '
      '$grid).',
    );
    return null;
  }
  if (!map.has('left') && !map.has('right')) {
    issues.error(map.blockLine, 'o molde precisa de `left` ou de `right`.');
    return null;
  }
  final rests = List.filled(grid, '.').join(' ');
  final left = map.get<String>('left') ?? rests;
  final right = map.get<String>('right') ?? rests;
  final leftBars = parseCompingLine(
    left,
    grid: grid,
    error: (m) => issues.error(map.lineOf('left'), '`left`: $m.'),
  );
  final rightBars = parseCompingLine(
    right,
    grid: grid,
    error: (m) => issues.error(map.lineOf('right'), '`right`: $m.'),
  );
  if (leftBars == null || rightBars == null) return null;
  if (leftBars.length != rightBars.length) {
    issues.error(
      map.lineOf('right'),
      '`left` tem ${leftBars.length} compasso(s) e `right` tem '
      '${rightBars.length}: as duas mãos têm de ter o mesmo.',
    );
    return null;
  }
  return CompingPattern(
    name: 'molde',
    grid: grid,
    left: left,
    right: right,
    time: null,
  );
}

/// `listen-chord` (EX04): a qualidade (com `qualities`, `roots`, `inversion` e
/// `play`) ou casa ou tensão (com `answer: function`, `key` e `degrees`). Cada
/// chave que não vale na forma escolhida é erro, com a linha dela.
ListenChordSpec? _listenChord(Fields f, _Head head, FileIssues issues) {
  final answer =
      _enumOf(ChordAnswerKind.values, f.get<String>('answer')) ??
      ChordAnswerKind.quality;
  final isFunction = answer == ChordAnswerKind.function;
  var ok = _checkNotHere(f, issues, answer, isFunction);
  final count = f.get<int>('count') ?? 10;

  var qualities = <String>[];
  NotesSpec? roots;
  if (!isFunction) {
    final read = _qualitiesOf(f, issues, head.line);
    qualities = read.qualities;
    if (!read.ok) ok = false;
    final rootRead = _rootsOf(f, issues, count);
    roots = rootRead.roots;
    if (!rootRead.ok) ok = false;
  }

  var degrees = <String>[];
  if (isFunction) {
    final read = _degreesOf(f, issues);
    degrees = read.degrees;
    if (!read.ok) ok = false;
  }
  if (!ok) return null;
  return ListenChordSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    answer: answer,
    count: count,
    play: _enumOf(ChordPlay.values, f.get<String>('play')) ?? ChordPlay.block,
    inversion:
        _enumOf(ChordInversionChoice.values, f.get<String>('inversion')) ??
        ChordInversionChoice.root,
    key: f.get<String>('key') ?? 'C',
    qualities: qualities,
    roots: roots,
    degrees: degrees,
  );
}

/// As chaves que não valem com a [answer]: as de uma resposta por função (grau)
/// não valem com a de qualidade, e o contrário. `false` (com o erro) se alguma
/// está escrita.
bool _checkNotHere(
  Fields f,
  FileIssues issues,
  ChordAnswerKind answer,
  bool isFunction,
) {
  var ok = true;
  final notHere = isFunction
      ? const ['qualities', 'roots', 'play', 'inversion']
      : const ['key', 'degrees'];
  for (final name in notHere) {
    if (f.has(name)) {
      issues.error(
        f.lineOf(name),
        '`$name` não vale com `answer: ${answer.wire}`.',
      );
      ok = false;
    }
  }
  return ok;
}

/// As qualidades que os botões mostram (`qualities:`): obrigatórias na resposta
/// por qualidade, conhecidas e sem repetição. `ok` diz se presta.
({List<String> qualities, bool ok}) _qualitiesOf(
  Fields f,
  FileIssues issues,
  int line,
) {
  var ok = true;
  var qualities = <String>[];
  if (f.has('qualities')) {
    qualities = f.get<List<Object>>('qualities')!.cast<String>();
    for (final (i, quality) in qualities.indexed) {
      if (!kChordQualities.containsKey(quality)) {
        final hint = suggestFor(quality, kChordQualities.keys);
        issues.error(
          _itemLine(f, 'qualities', i),
          'qualidade `$quality` desconhecida'
          '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
          '(use ${kChordQualities.keys.join(', ')}).',
        );
        ok = false;
      }
    }
    if (qualities.toSet().length != qualities.length) {
      issues.error(f.lineOf('qualities'), '`qualities` repete uma qualidade.');
      ok = false;
    }
  } else {
    issues.error(
      line,
      '`answer: quality` pede `qualities`: as qualidades que os botões mostram.',
    );
    ok = false;
  }
  return (qualities: qualities, ok: ok);
}

/// As raízes (`roots:`): uma lista de notas, ou o sorteio (com o [count] da
/// lição) quando não há `roots:`. `ok` diz se presta.
({NotesSpec? roots, bool ok}) _rootsOf(Fields f, FileIssues issues, int count) {
  if (!f.has('roots')) {
    return (
      roots: RandomNotes(
        range: NoteRange(Pitch.parse('C3'), Pitch.parse('G4')),
        count: count,
      ),
      ok: true,
    );
  }
  var ok = true;
  final raw = f.values['roots'];
  if (raw is Fields && raw.has('count')) {
    issues.error(
      raw.lineOf('count'),
      '`count` do sorteio de `roots` não vale: use o `count` da lição.',
    );
    ok = false;
  }
  if (raw is List && f.has('count')) {
    issues.error(
      f.lineOf('count'),
      '`count` não vale com `roots` em lista: uma pergunta por nota.',
    );
    ok = false;
  }
  final roots = _notes(
    f,
    issues,
    _NotesRule(defaultCount: count, key: 'roots'),
  );
  if (roots == null) ok = false;
  return (roots: roots, ok: ok);
}

/// Os graus (`degrees:`) de uma resposta por função: cada um tem que ser um
/// grau, e um grau de casa ou de tensão. `ok` diz se presta.
({List<String> degrees, bool ok}) _degreesOf(Fields f, FileIssues issues) {
  var ok = true;
  final degrees =
      f.get<List<Object>>('degrees')?.cast<String>() ??
      const ['I', 'IV', 'V', 'vi'];
  for (final (i, text) in degrees.indexed) {
    String? detail;
    final degree = ChordDegree.parse(text, error: (m) => detail = m);
    if (degree == null) {
      issues.error(
        _itemLine(f, 'degrees', i),
        '`$text` não é um grau: ${detail ?? 'não entendi'}.',
      );
      ok = false;
    } else if (degree.harmonicFunction == null) {
      issues.error(
        _itemLine(f, 'degrees', i),
        '`$text` não é casa nem tensão: use I, ii, iii, IV ou vi (casa), '
        'ou V, V7, vii° ou V7/x (tensão).',
      );
      ok = false;
    }
  }
  return (degrees: degrees, ok: ok);
}

/// As cifras de `chords:` já lidas e conferidas, com um [ChordSymbol] de
/// amostra por cifra (a do sorteio tem a raiz em dó), para as regras de
/// inversão e de molde.
typedef _Chords = ({ChordsSpec spec, List<ChordSymbol> samples});

/// `chords:` do `play-chord`: a lista fixa ou o sorteio. `null` se alguma
/// cifra, qualidade ou grau está errada (o erro já foi dado).
_Chords? _chords(Fields f, FileIssues issues) {
  final raw = f.values['chords'];
  if (raw is List) return _fixedChords(f, raw.cast<String>(), issues);
  return _chordsMap(raw as Fields, issues);
}

/// A lista fixa de cifras: cada uma tem de ler-se.
_Chords? _fixedChords(Fields f, List<String> symbols, FileIssues issues) {
  final samples = <ChordSymbol>[];
  var ok = true;
  for (final (i, text) in symbols.indexed) {
    String? detail;
    final symbol = ChordSymbol.parse(text, error: (m) => detail = m);
    if (symbol == null) {
      issues.error(
        _itemLine(f, 'chords', i),
        '`$text` não é uma cifra: ${detail ?? 'não entendi'}.',
      );
      ok = false;
    } else {
      samples.add(symbol);
    }
  }
  return ok ? (spec: FixedChords(symbols), samples: samples) : null;
}

/// O sorteio de `chords`: `qualities` (com `roots`) ou `degrees`, e não os dois.
_Chords? _chordsMap(Fields map, FileIssues issues) {
  final qualities = map.get<List<Object>>('qualities')?.cast<String>();
  final degrees = map.get<List<Object>>('degrees')?.cast<String>();
  if ((qualities == null) == (degrees == null)) {
    issues.error(
      map.lineOf('chords'),
      qualities == null
          ? 'falta `qualities` ou `degrees` em `chords`.'
          : 'use `qualities` **ou** `degrees`, não os dois.',
    );
    return null;
  }
  final qualitySamples = qualities == null
      ? const <ChordSymbol>[]
      : _qualitySamples(map, qualities, issues);
  final degreeSamples = degrees == null
      ? const <ChordSymbol>[]
      : _degreeSamples(map, degrees, issues);
  if (qualitySamples == null || degreeSamples == null) return null;
  final samples = [...qualitySamples, ...degreeSamples];

  final count = map.get<int>('count') ?? (qualities != null ? 10 : 1);
  final sequence = map.get<String>('sequence') ?? 'random';
  final key = map.get<String>('key') ?? 'C';
  if (qualities == null) {
    return (
      spec: DegreeChords(
        degrees: degrees!,
        count: count,
        sequence: sequence,
        key: key,
      ),
      samples: samples,
    );
  }
  return (
    spec: _randomChords(map, qualities, (
      count: count,
      sequence: sequence,
      key: key,
    )),
    samples: samples,
  );
}

/// O sorteio por qualidades; `roots` diz as raízes (`random`, `white` ou uma
/// lista de notas).
RandomChords _randomChords(
  Fields map,
  List<String> qualities,
  ({int count, String sequence, String key}) how,
) {
  final rawRoots = map.values['roots'];
  final roots = switch (rawRoots) {
    List() => rawRoots.cast<String>(),
    String() when rawRoots != 'random' && rawRoots != 'white' => [rawRoots],
    _ => null,
  };
  return RandomChords(
    qualities: qualities,
    count: how.count,
    sequence: how.sequence,
    roots: roots,
    whiteOnly: rawRoots == 'white',
    key: how.key,
  );
}

/// As cifras de exemplo das qualidades; `null` se alguma não existe.
List<ChordSymbol>? _qualitySamples(
  Fields map,
  List<String> qualities,
  FileIssues issues,
) {
  final samples = <ChordSymbol>[];
  var ok = true;
  for (final (i, quality) in qualities.indexed) {
    final suffix = kChordQualities[quality];
    if (suffix == null) {
      final hint = suggestFor(quality, kChordQualities.keys);
      issues.error(
        _itemLine(map, 'qualities', i),
        'qualidade `$quality` desconhecida'
        '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
        '(use ${kChordQualities.keys.join(', ')}).',
      );
      ok = false;
    } else {
      samples.add(ChordSymbol.parse('C$suffix')!);
    }
  }
  return ok ? samples : null;
}

/// Os graus de exemplo (na tonalidade de dó); `null` se algum não se lê.
List<ChordSymbol>? _degreeSamples(
  Fields map,
  List<String> degrees,
  FileIssues issues,
) {
  const dOfC = KeySpec(tonic: 0, minor: false, spelling: 'C');
  final samples = <ChordSymbol>[];
  var ok = true;
  for (final (i, text) in degrees.indexed) {
    String? detail;
    final degree = ChordDegree.parse(text, error: (m) => detail = m);
    if (degree == null) {
      issues.error(
        _itemLine(map, 'degrees', i),
        '`$text` não é um grau: ${detail ?? 'não entendi'}.',
      );
      ok = false;
    } else {
      samples.add(degree.inKey(dOfC));
    }
  }
  return ok ? samples : null;
}

/// A linha do item [i] da lista [key] de [f], ou a da própria chave.
int _itemLine(Fields f, String key, int i) =>
    f.itemLines[key]?[i] ?? f.lineOf(key);

/// Um passo do treino de leitura, `1a` a `100d`: o nível e o subnível.
final _stepPattern = RegExp(r'^(100|[1-9][0-9]?)([a-d])$');

/// `rhythm` (EX13): o sorteio (`figures`), o ABC (`abc`), ou um groove ou
/// moldes escritos (`groove`, ou `right` com `left`), com uma mão ou duas
/// (`hands`, e a nota que as separa, `split`). Os erros que cruzam chaves saem
/// aqui, cada um com a linha da chave que está errada.
RhythmSpec? _rhythm(Fields f, _Head head, FileIssues issues) {
  final r = _RhythmReader(f, issues);
  r.checkSource();
  r.checkGrooveTime();
  final figures = r.figures;
  if (r.abc == null &&
      figures != null &&
      !_figuresFit(figures, r.effective, f, issues)) {
    r.ok = false;
  }
  final hands = r.checkHands();
  r.checkSplit(hands);
  r.checkMolds();
  final measures = r.checkMeasures();
  if (!r.ok) return null;
  return RhythmSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    time: r.effective,
    bpm: f.get<int>('bpm') ?? 80,
    note: f.get<Pitch>('note') ?? Pitch.parse('C4'),
    figures: figures,
    measures: measures,
    abc: r.abc,
    hands: hands,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    groove: r.groove,
    right: r.right,
    left: r.left,
  );
}

/// A leitura de um exercício de ritmo, parte a parte: a fonte (o sorteio, o
/// `abc` escrito, o groove ou o molde), o compasso, as mãos, os moldes e os
/// compassos. Cada parte anota os erros (com a linha da chave) e marca [ok] se
/// algo não presta.
class _RhythmReader {
  _RhythmReader(this.f, this.issues)
    : abc = f.get<String>('abc'),
      time = f.get<String>('time'),
      groove = _grooveNamed(f) {
    molde = groove != null || f.has('right');
    effective = time ?? groove?.time ?? '4/4';
    figures = molde ? null : f.get<List<Object>>('figures')?.cast<Figure>();
  }

  final Fields f;
  final FileIssues issues;
  final String? abc;
  final String? time;
  final RhythmGroove? groove;
  late final bool molde;

  /// O compasso do exercício: o do groove (que ele tem de repetir), ou 4/4.
  late final String effective;
  late final List<Figure>? figures;
  var ok = true;
  List<List<RhythmSymbol>>? right;
  List<List<RhythmSymbol>>? left;

  static RhythmGroove? _grooveNamed(Fields f) {
    final grooveName = f.get<String>('groove');
    return grooveName == null ? null : rhythmGrooveNamed(grooveName);
  }

  /// A fonte: o groove e o molde não valem com as chaves do sorteio nem com o
  /// `abc`; o `abc` não vale com as do sorteio; e sem nenhuma fonte, é erro.
  void checkSource() {
    if (f.has('groove') && (f.has('right') || f.has('left'))) {
      issues.error(
        f.lineOf('groove'),
        '`groove` não vale com `right` e `left`: o groove já traz os moldes.',
      );
      ok = false;
    }
    if (molde) {
      _checkMoldeSource();
    } else if (abc != null) {
      _checkAbcSource();
    } else if (!f.has('figures') && !f.has('left')) {
      issues.error(
        f.blockLine,
        'informe `figures` (ritmo sorteado), `abc` (ritmo escrito), `groove` ou '
        '`right` (molde).',
      );
      ok = false;
    }
  }

  void _checkMoldeSource() {
    for (final key in ['figures', 'abc']) {
      if (f.has(key)) {
        issues.error(
          f.lineOf(key),
          '`$key` não vale com `groove` ou `right`: o ritmo é o molde.',
        );
        ok = false;
      }
    }
    if (f.has('note')) {
      issues.error(
        f.lineOf('note'),
        '`note` só vale no sorteio, com `figures`.',
      );
      ok = false;
    }
  }

  void _checkAbcSource() {
    for (final key in ['figures', 'measures', 'note']) {
      if (f.has(key)) {
        issues.error(
          f.lineOf(key),
          '`$key` só vale no sorteio; com `abc` o ritmo é o que está escrito.',
        );
        ok = false;
      }
    }
    if (time != null && abcIsComplete(abc!)) {
      issues.error(
        f.lineOf('time'),
        'um `abc` com `X:` já traz o cabeçalho: tire `time`.',
      );
      ok = false;
    }
  }

  /// O compasso do groove tem que ser o que o exercício pede.
  void checkGrooveTime() {
    final groove = this.groove;
    if (groove != null && time != null && time != groove.time) {
      issues.error(
        f.lineOf('time'),
        'o groove `${groove.name}` é de ${groove.time}, e o exercício é de '
        '$time.',
      );
      ok = false;
    }
  }

  /// As mãos: o groove diz as que toca; sem groove, duas mãos são as que têm
  /// `left:`, e `hands: two` sem `left:` é erro. Devolve quantas são.
  int checkHands() {
    final handsName = f.get<String>('hands');
    final groove = this.groove;
    if (groove != null) {
      if (handsName == 'one' && groove.hands == 2) {
        issues.error(
          f.lineOf('hands'),
          'o groove `${groove.name}` toca as duas mãos: tire `hands:`.',
        );
        ok = false;
      }
      if (handsName == 'two' && groove.hands == 1) {
        issues.error(
          f.lineOf('hands'),
          'o groove `${groove.name}` toca só a mão direita: tire `hands: two`.',
        );
        ok = false;
      }
      return groove.hands;
    }
    final twoHands = f.has('left');
    if (handsName == 'two' && !twoHands) {
      issues.error(
        f.lineOf('hands'),
        '`hands: two` pede `left:` ou um `groove` de duas mãos.',
      );
      ok = false;
    }
    if (handsName == 'one' && twoHands) {
      issues.error(f.lineOf('hands'), '`left:` não vale com `hands: one`.');
      ok = false;
    }
    return twoHands ? 2 : 1;
  }

  /// `split` só vale com duas mãos.
  void checkSplit(int hands) {
    if (f.has('split') && hands != 2) {
      issues.error(
        f.lineOf('split'),
        '`split` só vale com duas mãos (`hands: two`, ou um `groove` de duas '
        'mãos).',
      );
      ok = false;
    }
  }

  /// Os moldes: os do groove, ou os escritos (`right`, e `left` se tiver).
  void checkMolds() {
    final groove = this.groove;
    if (groove != null) {
      right = groove.rightBars;
      left = groove.left == null ? null : groove.leftBars;
    } else if (f.has('right')) {
      right = _moldeOf(f, 'right', effective, issues);
      if (f.has('left')) left = _moldeOf(f, 'left', effective, issues);
      if (right == null || (f.has('left') && left == null)) ok = false;
    } else if (f.has('left')) {
      issues.error(
        f.lineOf('left'),
        '`left` pede `right`: os dois moldes vêm juntos.',
      );
      ok = false;
    }
    final rightBars = right;
    final leftBars = left;
    if (rightBars != null &&
        leftBars != null &&
        rightBars.length != leftBars.length) {
      issues.error(
        f.lineOf('left'),
        '`left` tem ${leftBars.length} compasso(s) e `right` tem '
        '${rightBars.length}: as duas mãos têm de ter o mesmo número de '
        'compassos.',
      );
      ok = false;
    }
  }

  /// `measures` conta os compassos do exercício (4 por padrão), e o molde se
  /// repete até fechá-los: tem de ser múltiplo dos compassos do molde.
  int? checkMeasures() {
    var measures = figures == null ? null : (f.get<int>('measures') ?? 4);
    final right = this.right;
    if (right != null) {
      final bars = right.length;
      final given = f.get<int>('measures');
      final count = given ?? 4;
      measures = count;
      if (count % bars != 0) {
        issues.error(
          given != null
              ? f.lineOf('measures')
              : (groove != null ? f.lineOf('groove') : f.lineOf('right')),
          given != null
              ? '`measures` precisa ser múltiplo de $bars, o número de compassos '
                    'do molde (recebi $count).'
              : 'o molde tem $bars compasso(s), e `measures` (padrão 4) não é '
                    'múltiplo disso: escreva `measures:`.',
        );
        ok = false;
      }
    }
    return measures;
  }
}

/// Lê o molde escrito na chave [key] (`right` ou `left`) no compasso [time].
/// O erro vai para a linha da chave, com o nome dela na frente.
List<List<RhythmSymbol>>? _moldeOf(
  Fields f,
  String key,
  String time,
  FileIssues issues,
) => parseRhythmMolde(
  f.get<String>(key)!,
  time: time,
  error: (message) => issues.error(f.lineOf(key), '`$key`: $message.'),
);

/// `listen-groove` (EX13): os grooves que os botões mostram (dois ou mais, com
/// os nomes do vocabulário; um nome que não existe tem sugestão) e as
/// perguntas.
ListenGrooveSpec? _listenGroove(Fields f, _Head head, FileIssues issues) {
  final id = head.id;
  final title = head.title;
  final line = head.line;
  final pass = head.pass;
  final names = f.get<List<Object>>('grooves')!.cast<String>();
  final wires = [for (final groove in ListenGroove.values) groove.wire];
  var ok = true;
  final grooves = <ListenGroove>[];
  for (final (i, name) in names.indexed) {
    final groove = ListenGroove.values.where((g) => g.wire == name).firstOrNull;
    if (groove == null) {
      final hint = suggestFor(name, wires);
      issues.error(
        _itemLine(f, 'grooves', i),
        'groove `$name` desconhecido'
        '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
        '(use ${wires.join(', ')}).',
      );
      ok = false;
    } else {
      grooves.add(groove);
    }
  }
  if (grooves.toSet().length != grooves.length) {
    issues.error(f.lineOf('grooves'), '`grooves` repete um groove.');
    ok = false;
  }
  if (!ok) return null;
  return ListenGrooveSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    grooves: grooves,
    count: f.get<int>('count') ?? 8,
  );
}

/// `listen-progression` (EX15): as progressões (um nome da biblioteca ou uma
/// grade escrita, de até 8 acordes, sem graus repetidos), a resposta, o tom, a
/// base e o andamento. Com `choice`, são duas ou mais. O nome da biblioteca sai
/// da grade dela, para o app ter só grades.
ListenProgressionSpec? _listenProgression(
  Fields f,
  _Head head,
  FileIssues issues,
) {
  final answer = _choice(
    f,
    'answer',
    ProgressionAnswer.values,
    ProgressionAnswer.choice,
  );
  final given = f.get<List<Object>>('progressions')!.cast<String>();
  final countOk = _progressionCountOk(f, answer, given.length, issues);
  final charts = _progressionCharts(f, given, issues);
  final style = _progressionStyle(f, issues);
  if (!countOk || charts == null || !style.ok) return null;
  return _progressionSpec(f, head, (
    answer: answer,
    charts: charts,
    style: style.style,
  ));
}

/// O que `listen-progression` já conferiu e o spec leva.
typedef _ProgressionParts = ({
  ProgressionAnswer answer,
  List<String> charts,
  BackingStyle? style,
});

ListenProgressionSpec _progressionSpec(
  Fields f,
  _Head head,
  _ProgressionParts p,
) {
  return ListenProgressionSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    answer: p.answer,
    progressions: p.charts,
    key: f.get<String>('key') ?? 'C',
    style: p.style,
    bpm: f.get<int>('bpm') ?? 90,
    count: f.get<int>('count') ?? 8,
  );
}

/// Com `answer: choice` são precisas duas ou mais progressões: os botões
/// escolhem entre elas.
bool _progressionCountOk(
  Fields f,
  ProgressionAnswer answer,
  int count,
  FileIssues issues,
) {
  if (answer != ProgressionAnswer.choice || count >= 2) return true;
  issues.error(
    f.lineOf('progressions'),
    '`answer: choice` pede duas ou mais progressões: os botões escolhem entre '
    'elas.',
  );
  return false;
}

/// As progressões escritas, na ordem; `null` se alguma não vale.
List<String>? _progressionCharts(
  Fields f,
  List<String> given,
  FileIssues issues,
) {
  final charts = <String>[];
  final spelled = <String>{};
  var ok = true;
  for (final (i, text) in given.indexed) {
    final chart = _progressionChart(
      text,
      _itemLine(f, 'progressions', i),
      spelled,
      issues,
    );
    if (chart == null) {
      ok = false;
    } else {
      charts.add(chart);
    }
  }
  return ok ? charts : null;
}

/// Uma progressão: a da biblioteca ou a grade escrita, com até 8 acordes e
/// sem os graus de uma anterior ([spelled]). `null`, com o erro, se não vale.
String? _progressionChart(
  String text,
  int line,
  Set<String> spelled,
  FileIssues issues,
) {
  final chart = progressionNamed(text)?.chart ?? text;
  String? detail;
  final bars = parseProgression(chart, error: (m) => detail = m);
  if (bars == null) {
    final hint = suggestFor(text, [for (final p in kProgressions) p.name]);
    issues.error(
      line,
      '`$text` não é uma progressão da biblioteca'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}, nem uma grade '
      'escrita${detail != null ? ' ($detail)' : ''}: escreva os graus '
      'separados por espaço e os compassos por `|`, como `I | vi | ii V | I`.',
    );
    return null;
  }
  final chords = bars.fold<int>(0, (sum, bar) => sum + bar.length);
  if (chords > 8) {
    issues.error(
      line,
      '`$text` tem $chords acordes: o máximo é 8 (é longo demais para o '
      'ouvido).',
    );
    return null;
  }
  final degrees = [
    for (final bar in bars)
      for (final degree in bar) degree.label,
  ].join(' ');
  if (!spelled.add(degrees)) {
    issues.error(
      line,
      '`$text` tem os mesmos graus de uma progressão anterior.',
    );
    return null;
  }
  return chart;
}

/// O estilo da base (`style`; `block` é só a melodia, sem base). Só vale em
/// 4/4: [ok] é falso se o estilo é de outro compasso.
({BackingStyle? style, bool ok}) _progressionStyle(
  Fields f,
  FileIssues issues,
) {
  final styleName = f.get<String>('style') ?? 'block';
  if (styleName == 'block') return (style: null, ok: true);
  final style = backingStyleNamed(styleName);
  if (style != null && style.time != '4/4') {
    issues.error(
      f.lineOf('style'),
      'o estilo `${style.name}` é de ${style.time}, e a progressão é em 4/4.',
    );
    return (style: style, ok: false);
  }
  return (style: style, ok: true);
}

/// `harmonize` (EX16): o modo, a melodia (`step` gerada ou `file` do autor), os
/// graus que o acorde pode ser, onde ele troca e o molde. O que depende da nota
/// (se um acorde cabe no compasso, a fórmula da melodia) é do app, que lê a
/// melodia. `null` com erro (o erro já saiu).
HarmonizeSpec? _harmonize(Fields f, _Head head, FileIssues issues) {
  final modeRead = _harmonizeMode(f, issues);
  var ok = modeRead.ok;
  final mode = modeRead.mode;
  // Sem `melody:` a leitura da chave já disse o que falta.
  final melodyRead = _harmonizeMelody(f, issues);
  if (melodyRead == null) return null;
  if (!melodyRead.ok) ok = false;
  final melody = melodyRead.melody;
  final chordRead = _harmonizeChords(f, issues);
  if (!chordRead.ok) ok = false;
  final changeRead = _harmonizeChange(f, issues, melody);
  if (!changeRead.ok) ok = false;
  final patternRead = _harmonizePatternOf(f, issues, mode);
  if (!patternRead.ok) ok = false;
  if (!ok) return null;
  return HarmonizeSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    mode: mode,
    melody: melody,
    chords: chordRead.chords,
    change: changeRead.change,
    pattern: mode == HarmonizeMode.degrees ? null : patternRead.name,
    bpm: f.get<int>('bpm') ?? 70,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    count: f.get<int>('count') ?? 1,
  );
}

/// O modo (`mode:`). A rearmonização (nível 6) está no formato, mas ainda não
/// roda; e o `technique` só vale com ela.
({HarmonizeMode mode, bool ok}) _harmonizeMode(Fields f, FileIssues issues) {
  var ok = true;
  final mode =
      _enumOf(HarmonizeMode.values, f.get<String>('mode')) ??
      HarmonizeMode.play;
  if (mode == HarmonizeMode.reharmonize) {
    issues.error(
      f.lineOf('mode'),
      '`mode: reharmonize` ainda não roda: a rearmonização (nível 6) fica '
      'para depois.',
    );
    ok = false;
  }
  if (f.has('technique')) {
    issues.error(
      f.lineOf('technique'),
      '`technique` só vale com `mode: reharmonize`, que ainda não roda.',
    );
    ok = false;
  }
  return (mode: mode, ok: ok);
}

/// A melodia (`melody:`): um passo gerado (com a chave), ou um arquivo. `null`
/// se não há `melody:` ou se ela tem as duas formas (ou nenhuma); `ok` diz se o
/// resto presta.
({MelodySource melody, bool ok})? _harmonizeMelody(
  Fields f,
  FileIssues issues,
) {
  final map = f.values['melody'] as Fields?;
  if (map == null) return null;
  final step = map.get<String>('step');
  final file = map.get<String>('file');
  if ((step == null) == (file == null)) {
    issues.error(
      f.lineOf('melody'),
      '`melody` pede uma das duas formas: `{step, key}` (uma melodia gerada) '
      'ou `{file}` (um `.musicxml` da pasta).',
    );
    return null;
  }
  var ok = true;
  final MelodySource melody;
  if (step != null) {
    if (!_stepPattern.hasMatch(step)) {
      issues.error(
        map.lineOf('step'),
        '`step` `$step` não é um passo da leitura: use `1a` a `100d`.',
      );
      ok = false;
    }
    melody = StepMelody(step: step, key: map.get<String>('key'));
  } else {
    if (map.has('key')) {
      issues.error(
        map.lineOf('key'),
        '`key` não vale com `file`: o tom vem da armadura do arquivo.',
      );
      ok = false;
    }
    melody = FileMelody(file!);
  }
  if (melody is FileMelody && f.has('count')) {
    issues.error(
      f.lineOf('count'),
      '`count` só vale com `step`: a melodia do arquivo é uma só.',
    );
    ok = false;
  }
  return (melody: melody, ok: ok);
}

/// As cifras (`chords:`, os graus romanos). `ok` diz se todas se leem.
({List<String> chords, bool ok}) _harmonizeChords(Fields f, FileIssues issues) {
  var ok = true;
  final chords =
      f.get<List<Object>>('chords')?.cast<String>() ?? const ['I', 'IV', 'V7'];
  for (final (i, text) in chords.indexed) {
    if (ChordDegree.parse(text) == null) {
      issues.error(
        _itemLine(f, 'chords', i),
        '`$text` não é um grau: use romanos, como `I`, `ii`, `V7` ou `V7/vi`.',
      );
      ok = false;
    }
  }
  return (chords: chords, ok: ok);
}

/// A troca de cifra (`change:`): a `marked` pede uma melodia do autor (com as
/// marcas), e a gerada não as tem.
({HarmonizeChange change, bool ok}) _harmonizeChange(
  Fields f,
  FileIssues issues,
  MelodySource melody,
) {
  final change =
      _enumOf(HarmonizeChange.values, f.get<String>('change')) ??
      HarmonizeChange.bar;
  if (change == HarmonizeChange.marked && melody is StepMelody) {
    issues.error(
      f.lineOf('change'),
      '`change: marked` pede uma melodia do autor (`file`): a melodia gerada '
      'não tem marcas de troca.',
    );
    return (change: change, ok: false);
  }
  return (change: change, ok: true);
}

/// O molde (`pattern:`): só vale com `play` e `by-ear` (com `degrees` não há).
/// `block` é o acorde na esquerda nos tempos 1 e 3 (a direita é a melodia; ver
/// o EX16); os outros são os do EX11.
({String name, bool ok}) _harmonizePatternOf(
  Fields f,
  FileIssues issues,
  HarmonizeMode mode,
) {
  var ok = true;
  final pattern = f.get<String>('pattern');
  if (mode == HarmonizeMode.degrees && pattern != null) {
    issues.error(
      f.lineOf('pattern'),
      '`pattern` não vale com `mode: degrees`: o trecho só pede o grau.',
    );
    ok = false;
  }
  final name = pattern ?? 'block';
  if (mode != HarmonizeMode.degrees && !_harmonizePattern(name)) {
    final hint = suggestFor(name, ['block', 'any', ...compingPatternNames]);
    issues.error(
      f.lineOf('pattern'),
      'não há o molde `$name`'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    ok = false;
  }
  return (name: name, ok: ok);
}

/// Os moldes que o `harmonize` aceita: `block` (o dele), `any` e os do EX11.
bool _harmonizePattern(String name) =>
    name == 'block' || name == 'any' || compingPatternNamed(name) != null;

/// `play-lead-sheet` (EX17): a melodia do `file` (com as cifras), o molde ou o
/// estilo, o que a melodia confere (`melody`), o andamento e o tom da mão. O que
/// depende da partitura (se as cifras se leem, se o estilo cabe nos compassos)
/// é do app. Recusa o que ainda não roda: `abc`, o tom por rodada, a base e os
/// estilos fora de [LeadStyle.implemented]. `null` com erro (o erro já saiu).
PlayLeadSheetSpec? _playLeadSheet(Fields f, _Head head, FileIssues issues) {
  final sourceOk = _leadSourceRules(f, issues);
  final styleOk = _leadStyleRules(f, issues);
  if (!sourceOk || !styleOk) return null;
  return _leadSheetSpec(f, head);
}

/// A fonte da cifra: o `play-lead-sheet` lê o `.musicxml` (`file`); o que ainda
/// não roda (`abc`, `keys`, `cycle`, `key-start`, `backing`) dá erro.
bool _leadSourceRules(Fields f, FileIssues issues) {
  var ok = true;
  if (!f.has('file') && !f.has('abc')) {
    issues.error(
      f.lineOf('file'),
      'o `play-lead-sheet` precisa de `file`: o `.musicxml` com a melodia e as '
      'cifras (`<harmony>`).',
    );
    ok = false;
  }
  if (f.has('abc')) {
    issues.error(
      f.lineOf('abc'),
      '`abc` ainda não roda no `play-lead-sheet`: o zywny só lê as cifras de '
      'um `.musicxml` (use `file`).',
    );
    ok = false;
  }
  for (final key in ['keys', 'cycle', 'key-start', 'backing']) {
    if (!f.has(key)) continue;
    issues.error(
      f.lineOf(key),
      '`$key` ainda não roda no `play-lead-sheet` (o tom por rodada e a base '
      'ficam para depois).',
    );
    ok = false;
  }
  return ok;
}

/// O estilo e o molde da mão esquerda: o estilo tem de rodar, e `pattern` não
/// vale com ele.
bool _leadStyleRules(Fields f, FileIssues issues) {
  var ok = true;
  final styleName = f.get<String>('style');
  final style = _enumOf(LeadStyle.values, styleName);
  if (style != null && !LeadStyle.implemented.contains(style)) {
    issues.error(
      f.lineOf('style'),
      '`style: $styleName` ainda não roda: o estilo espera o passo que o traz '
      '(use um molde de `pattern`, ou um dos estilos que rodam: '
      '${[for (final s in LeadStyle.implemented) s.wire].join(', ')}).',
    );
    ok = false;
  }
  if (style != null && f.has('pattern')) {
    issues.error(
      f.lineOf('pattern'),
      '`pattern` não vale com `style`: o estilo é o que a mão esquerda faz.',
    );
    ok = false;
  }
  final name = f.get<String>('pattern') ?? 'block';
  if (style == null && !_harmonizePattern(name)) {
    final hint = suggestFor(name, ['block', 'any', ...compingPatternNames]);
    issues.error(
      f.lineOf('pattern'),
      'não há o molde `$name`'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    ok = false;
  }
  return ok;
}

PlayLeadSheetSpec _leadSheetSpec(Fields f, _Head head) {
  return PlayLeadSheetSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    file: f.get<String>('file') ?? '',
    pattern: f.get<String>('pattern') ?? 'block',
    style: _enumOf(LeadStyle.values, f.get<String>('style')),
    melody: _choice(f, 'melody', LeadMelody.values, LeadMelody.check),
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing'),
    split: _splitOf(f),
  );
}

/// `echo` (EX14): a fonte das notas (`source:`, uma das três formas), a faixa, o
/// tamanho e o andamento das frases, e a conferência (`octave`, `rhythm`, a mão).
/// `null` com erro (o erro já saiu).
EchoSpec? _echo(Fields f, _Head head, FileIssues issues) {
  final src = _echoSourceOf(f, issues);
  if (src == null) return null;
  final chart = _echoChartOf(f, issues, chordTones: src.chordTones);
  final backing = _echoBacking(f, issues);
  final ok = src.ok && chart.ok && !(f.has('backing') && backing == null);
  final range = src.range;
  if (!ok || range == null) return null;
  return EchoSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    source: src.source,
    range: range,
    notes: f.get<int>('notes') ?? 4,
    figures: f.get<List<Object>>('figures')?.cast<Figure>() ?? [Figure.quarter],
    measures: f.get<int>('measures') ?? 1,
    leaps: f.get<int>('leaps') ?? 3,
    start: _choice(f, 'start', EchoStart.values, EchoStart.tonic),
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing') ?? 50,
    count: f.get<int>('count') ?? 8,
    octave: _choice(f, 'octave', EchoOctave.values, EchoOctave.any),
    transpose: _choice(
      f,
      'transpose',
      EchoTranspose.values,
      EchoTranspose.none,
    ),
    rhythm: _choice(f, 'rhythm', EchoRhythm.values, EchoRhythm.loose),
    split: _splitOf(f),
    hand: f.get<String>('hand') == 'left' ? HandChoice.left : HandChoice.right,
    backing: backing,
    chartText: chart.chartText,
    progression: chart.progression,
    progressionBars: chart.progressionBars,
    chartKey: chart.chartKey,
  );
}

/// O `source:` do `echo`: a fonte (escala, acordes ou frases), a faixa e o que
/// não vale com ela. `null` (o erro já saiu) se não há exatamente uma das três
/// formas; o [ok] diz se o resto presta.
({EchoSource source, NoteRange? range, bool chordTones, bool ok})?
_echoSourceOf(Fields f, FileIssues issues) {
  // Sem `source:` a leitura do campo obrigatório já disse o que falta.
  final map = f.values['source'] as Fields?;
  if (map == null) return null;
  var ok = true;
  final scale = map.get<String>('scale');
  final chordTones = map.get<bool>('chord-tones') ?? false;
  final licks = map.get<String>('licks');
  final forms = [scale, if (chordTones) 'chord-tones', licks].nonNulls.length;
  if (forms != 1) {
    issues.error(
      f.lineOf('source'),
      '`source` pede uma das três formas: `{scale, key, range}`, '
      '`{chord-tones: true}` ou `{licks: <biblioteca>}`.',
    );
    return null;
  }
  final rangeText = map.get<String>('range') ?? 'C4-C6';
  final range = NoteRange.tryParse(rangeText);
  if (range == null) {
    issues.error(
      map.lineOf('range'),
      '`range`: `$rangeText` não é uma faixa de notas, como C4-G5.',
    );
    ok = false;
  }
  final EchoSource source;
  if (scale != null) {
    source = EchoScaleSource(
      scale: ScaleKind.values.firstWhere((s) => s.wire == scale),
      key: map.get<String>('key') ?? 'C',
    );
  } else if (chordTones) {
    source = const EchoChordSource();
  } else {
    source = EchoLickSource(licks!);
  }

  // Sem `scale`, o tom é o da grade (ou dó): um `key:` na fonte não faria efeito.
  if (scale == null && map.has('key')) {
    issues.error(
      map.lineOf('key'),
      '`key` só vale com `scale`: com `licks` ou `chord-tones`, o tom é o da '
      'grade (ou dó).',
    );
    ok = false;
  }
  // Com `licks`, a frase vem da biblioteca: estas chaves não fazem efeito.
  if (licks != null && !_lickKeysFit(f, issues)) ok = false;
  return (source: source, range: range, chordTones: chordTones, ok: ok);
}

/// Com `licks`, as chaves da frase (`notes`, `figures`, `leaps`, `start`) não
/// valem: a frase vem da biblioteca. `false` (com o erro) se alguma está escrita.
bool _lickKeysFit(Fields f, FileIssues issues) {
  var ok = true;
  for (final key in ['notes', 'figures', 'leaps', 'start']) {
    if (!f.has(key)) continue;
    issues.error(
      f.lineOf(key),
      '`$key` não vale com `licks`: a frase vem da biblioteca.',
    );
    ok = false;
  }
  return ok;
}

/// A grade do `echo` (`chart:`, o acorde de cada compasso): o texto, ou a
/// progressão da biblioteca, e o tom. `chord-tones` pede a grade.
({
  String? chartText,
  String? progression,
  String chartKey,
  int? progressionBars,
  bool ok,
})
_echoChartOf(Fields f, FileIssues issues, {required bool chordTones}) {
  var ok = true;
  final chart = f.values['chart'];
  final chartMap = chart is Fields ? chart : null;
  final chartText = chartMap == null ? chart as String? : null;
  final progression = chartMap?.get<String>('progression');
  final chartKey = chartMap?.get<String>('key') ?? 'C';
  if (chordTones && chart == null) {
    issues.error(
      f.lineOf('source'),
      '`chord-tones` pede a grade: escreva `chart:` (o acorde de cada compasso).',
    );
    ok = false;
  }
  if (chart != null &&
      !_gradeOf(
        issues: issues,
        reading: (
          text: chartText,
          progression: progression,
          key: chartKey,
          time: '4/4',
          textLine: f.lineOf('chart'),
          progressionLine: chartMap?.lineOf('progression') ?? f.lineOf('chart'),
        ),
      )) {
    ok = false;
  }
  return (
    chartText: chartText,
    progression: progression,
    chartKey: chartKey,
    progressionBars: chartMap?.get<int>('bars'),
    ok: ok,
  );
}

/// O `backing:` do `echo` (EX14): o texto `drums` ou o mapa da base, como no
/// `play-chart`, mas sem molde: sem `style:`, é o `straight`. `null` sem
/// `backing:` ou com erro (o erro já saiu).
BackingSpec? _echoBacking(Fields f, FileIssues issues) {
  final raw = f.values['backing'];
  if (raw == null) return null;
  final map = raw is Fields ? raw : null;
  final name = map?.get<String>('style') ?? 'straight';
  final style = backingStyleNamed(name);
  if (style == null) {
    final hint = suggestFor(name, backingStyleNames);
    issues.error(
      map?.lineOf('style') ?? f.lineOf('backing'),
      'não há o estilo `$name` na tabela de estilos'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    return null;
  }
  if (style.time != '4/4') {
    issues.error(
      f.lineOf('backing'),
      'o estilo `${style.name}` é de ${style.time}, e o echo é em 4/4.',
    );
    return null;
  }
  final bass = BackingBass.values.firstWhere(
    (b) =>
        b.wire ==
        (map?.get<String>('bass') ?? (map == null ? 'none' : 'root-fifth')),
  );
  return BackingSpec(
    style: style,
    drums: map?.get<bool>('drums') ?? true,
    bass: bass,
    volume: map?.get<int>('volume') ?? 70,
    intro: map?.get<int>('intro') ?? 1,
  );
}

/// `theory-quiz` (EX21): os tópicos (a rodada divide as perguntas entre eles),
/// os tons, o número de perguntas, a resposta e as qualidades dos acordes. Os
/// erros de combinação saem aqui: o tópico da forma (ainda não roda), o teclado
/// sem tópico de nota ou acorde, o `interval-build` com botões e a qualidade
/// sem tópico de acorde.
TheoryQuizSpec? _theoryQuiz(Fields f, _Head head, FileIssues issues) {
  final topics = _theoryTopics(f, issues);
  final keys = _theoryKeys(f, issues);
  if (topics == null || keys == null) return null;
  final answer = _choice(
    f,
    'answer',
    TheoryAnswer.values,
    TheoryAnswer.buttons,
  );
  final answerOk = _theoryAnswerOk(f, topics, answer, issues);
  final qualitiesOk = _theoryQualitiesOk(f, topics, issues);
  if (!answerOk || !qualitiesOk) return null;
  return TheoryQuizSpec(
    id: head.id,
    title: head.title,
    pass: _pass(head.pass),
    line: head.line,
    topics: topics,
    keys: keys,
    count: f.get<int>('count') ?? 10,
    answer: answer,
    qualities: _stringsOf(f.get<Object>('qualities')) ?? const ['M', 'm'],
  );
}

/// `answer: keyboard` pede um tópico de nota ou acorde, e `interval-build` só se
/// responde no teclado.
bool _theoryAnswerOk(
  Fields f,
  List<TheoryTopic> topics,
  TheoryAnswer answer,
  FileIssues issues,
) {
  var ok = true;
  if (answer == TheoryAnswer.keyboard && !topics.any(_answersNote)) {
    issues.error(
      f.lineOf('answer'),
      '`answer: keyboard` pede um tópico de nota ou acorde (`scale-degree`, '
      '`interval-build`, `chord-tones` ou `black-key-count`).',
    );
    ok = false;
  }
  if (topics.contains(TheoryTopic.intervalBuild) &&
      answer != TheoryAnswer.keyboard) {
    issues.error(
      f.lineOf('answer'),
      '`interval-build` só se responde no teclado: use `answer: keyboard`.',
    );
    ok = false;
  }
  return ok;
}

/// `qualities` só vale com um tópico de acorde, e cada uma é qualidade do
/// formato.
bool _theoryQualitiesOk(Fields f, List<TheoryTopic> topics, FileIssues issues) {
  var ok = true;
  if (f.has('qualities') && !topics.any(_chordTopics)) {
    issues.error(
      f.lineOf('qualities'),
      '`qualities` só vale com `chord-tones` ou `chord-from-staff`.',
    );
    ok = false;
  }
  final qualities = _stringsOf(f.get<Object>('qualities')) ?? const ['M', 'm'];
  for (final quality in qualities) {
    if (kTheoryQualities.contains(quality)) continue;
    issues.error(
      f.lineOf('qualities'),
      '`$quality` não é uma qualidade de acorde do formato: use '
      '${kTheoryQualities.join(', ')}.',
    );
    ok = false;
  }
  return ok;
}

/// Os tópicos do `theory-quiz`, na ordem do autor. O da forma ainda não roda.
List<TheoryTopic>? _theoryTopics(Fields f, FileIssues issues) {
  final names = _stringsOf(f.get<Object>('topics'));
  if (names == null) return null;
  // O leitor do campo já recusou os nomes que não existem.
  final topics = [for (final name in names) _enumOf(TheoryTopic.values, name)!];
  if (topics.contains(TheoryTopic.formTemplate)) {
    issues.error(
      f.lineOf('topics'),
      '`form-template` ainda não roda: a forma e o modelo harmônico são texto '
      'das lições, fora do `theory-quiz`.',
    );
    return null;
  }
  return topics;
}

/// As tônicas do `theory-quiz`: `all` são os 12 tons; uma lista traz só a
/// tônica, sem `m` (o modo vem do tópico); o padrão é `[C, G, F]`.
List<String>? _theoryKeys(Fields f, FileIssues issues) {
  final raw = f.get<Object>('keys');
  if (raw == null) return const ['C', 'G', 'F'];
  if (raw == 'all') return kTheoryAllKeys;
  if (raw is! List<Object>) {
    issues.error(
      f.lineOf('keys'),
      '`keys: random` não vale no `theory-quiz`: use `all` ou uma lista de tônicas.',
    );
    return null;
  }
  final names = raw.cast<String>();
  for (final name in names) {
    if (name.endsWith('m')) {
      issues.error(
        f.lineOf('keys'),
        '`$name` é um tom menor: escreva só a tônica (como `A` para Lá menor). '
        'O modo vem do tópico.',
      );
      return null;
    }
  }
  return names;
}

/// Um texto ou uma lista de textos, como lista; `null` se a chave não está.
List<String>? _stringsOf(Object? value) => switch (value) {
  null => null,
  final String text => [text],
  final List<Object> items => items.cast<String>(),
  _ => null,
};

/// Os tópicos que respondem com nota (o teclado vale neles).
bool _answersNote(TheoryTopic topic) => switch (topic) {
  TheoryTopic.scaleDegree ||
  TheoryTopic.intervalBuild ||
  TheoryTopic.chordTones ||
  TheoryTopic.blackKeyCount => true,
  _ => false,
};

/// Os tópicos que pedem uma qualidade de acorde (`qualities:`).
bool _chordTopics(TheoryTopic topic) =>
    topic == TheoryTopic.chordTones || topic == TheoryTopic.chordFromStaff;

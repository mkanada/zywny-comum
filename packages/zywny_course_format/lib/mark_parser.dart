import 'package:yaml/yaml.dart';

import 'course_issue.dart';
import 'course_model.dart';
import 'field_reader.dart';
import 'figure_rules.dart';
import 'lesson_scanner.dart';

import 'package:zywny_music/note_name.dart';

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
    firstLine: mark.bodyLine,
    blockLine: mark.line,
    where: where,
  );
  if (fields.failed) return null;
  final before = issues.errorCount;
  final block = switch (mark.name) {
    'score' => _score(fields, mark, issues),
    'keyboard' => _keyboard(fields, mark, issues),
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

T? _enumOf<T extends WireEnum>(List<T> values, String? wire) =>
    wire == null ? null : values.firstWhere((v) => v.wire == wire);

ExerciseSpec? _parseExercise(
  YamlMap map,
  MarkSegment mark,
  FieldReader reader,
  FileIssues issues,
) {
  final typeNode = map.nodes['type'];
  final wires = ExerciseType.values.map((t) => t.wire).toList();
  final typeName = typeNode?.value;
  final type = typeName is String
      ? ExerciseType.values.where((t) => t.wire == typeName).firstOrNull
      : null;
  if (type == null) {
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

  final f = reader.read(
    map,
    exerciseKeys(type),
    firstLine: mark.bodyLine,
    blockLine: mark.line,
    where: 'no exercício `${type.wire}`',
  );
  final before = issues.errorCount;
  // `pass` é conferido mesmo se outra chave falhou: o autor vê tudo de uma vez.
  _checkPass(
    type,
    f.get<Fields>('pass'),
    issues,
    realtime:
        type == ExerciseType.rhythm ||
        (type == ExerciseType.playScore && f.get<String>('mode') == 'realtime'),
  );
  if (f.failed) return null;
  final spec = _buildExercise(type, f, mark, issues);
  return issues.errorCount > before ? null : spec;
}

PassCriteria _pass(Fields? pass) => PassCriteria(
  accuracy: pass?.get<int>('accuracy') ?? 90,
  rounds: pass?.get<int>('rounds') ?? 1,
  speed: pass?.get<int>('speed') ?? 100,
  timeLimit: pass?.get<int>('time-limit'),
);

/// `pass` só pode ter as chaves que valem no tipo (e `speed` só com tempo
/// real).
void _checkPass(
  ExerciseType type,
  Fields? pass,
  FileIssues issues, {
  required bool realtime,
}) {
  if (pass == null) return;
  for (final key in pass.values.keys) {
    final rule = kPassKeys[key]!;
    if (!rule.types.contains(type)) {
      issues.error(
        pass.lineOf(key),
        '`$key` não vale em `${type.wire}`: ${rule.note ?? 'ver a '
                'especificação'}.',
      );
    } else if (key == 'speed' && !realtime) {
      issues.error(
        pass.lineOf(key),
        'o modo espera não tem andamento: tire `speed` ou use '
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

/// `notes` como [NotesSpec]; confere faixa, `only` e quantidade. [letters]
/// e [naturalsOnly] valem para o `name-note`.
NotesSpec? _notes(
  Fields f,
  FileIssues issues, {
  required int defaultCount,
  bool naturalsOnly = false,
  List<String>? letters,
}) {
  final raw = f.values['notes'];
  final line = f.lineOf('notes');
  if (raw is List) {
    final notes = raw.cast<Pitch>();
    for (final pitch in notes) {
      if (naturalsOnly && !pitch.isNatural) {
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
  final random = raw as Fields;
  if (random.failed) return null;
  final range = NoteRange.tryParse(random.get<String>('random')!);
  final rangeLine = random.lineOf('random');
  if (range == null) {
    issues.error(
      rangeLine,
      '`${random.get<String>('random')}` não é uma faixa de notas: escreva '
      'da mais grave para a mais aguda, como C4-G5.',
    );
    return null;
  }
  final only = _enumOf(OnlyOn.values, random.get<String>('only'));
  if (range.to.midi == range.from.midi) {
    issues.error(
      rangeLine,
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
    count: random.get<int>('count') ?? defaultCount,
    only: only,
  );
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

ExerciseSpec? _buildExercise(
  ExerciseType type,
  Fields f,
  MarkSegment mark,
  FileIssues issues,
) {
  final pass = f.get<Fields>('pass');
  final id = f.get<String>('id')!;
  final title = f.get<String>('title')!;
  final line = mark.line;

  switch (type) {
    case ExerciseType.findKey:
      final notes = _notes(f, issues, defaultCount: 10);
      if (notes == null) return null;
      return FindKeySpec(
        id: id,
        title: title,
        pass: _pass(pass),
        line: line,
        notes: notes,
        octave:
            _enumOf(OctaveRule.values, f.get<String>('octave')) ??
            OctaveRule.any,
      );
    case ExerciseType.playNotes:
      final notes = _notes(f, issues, defaultCount: 12);
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
    case ExerciseType.nameNote:
      final choices =
          f.get<List<Object>>('choices')?.cast<String>() ??
          const ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
      final notes = _notes(
        f,
        issues,
        defaultCount: 12,
        naturalsOnly: true,
        letters: choices,
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
    case ExerciseType.rhythm:
      return _rhythm(f, id, title, line, pass, issues);
    case ExerciseType.countBeats:
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
    case ExerciseType.playScore:
      final mode =
          _enumOf(PlayMode.values, f.get<String>('mode')) ?? PlayMode.wait;
      final source = _scoreSource(f, issues);
      if (source == null) return null;
      return PlayScoreSpec(
        id: id,
        title: title,
        pass: _pass(pass),
        line: line,
        source: source,
        hand:
            _enumOf(HandChoice.values, f.get<String>('hand')) ??
            HandChoice.both,
        mode: mode,
        bpm: f.get<int>('bpm'),
        measures: f.get<MeasureRange>('measures'),
      );
    case ExerciseType.choice:
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
}

RhythmSpec? _rhythm(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  final abc = f.get<String>('abc');
  final time = f.get<String>('time');
  var ok = true;
  if (abc != null) {
    for (final key in ['figures', 'measures', 'note']) {
      if (f.has(key)) {
        issues.error(
          f.lineOf(key),
          '`$key` só vale no sorteio; com `abc` o ritmo é o que está escrito.',
        );
        ok = false;
      }
    }
    if (time != null && abcIsComplete(abc)) {
      issues.error(
        f.lineOf('time'),
        'um `abc` com `X:` já traz o cabeçalho: tire `time`.',
      );
      ok = false;
    }
  } else if (!f.has('figures')) {
    issues.error(
      f.blockLine,
      'informe `figures` (ritmo sorteado) ou `abc` (ritmo escrito).',
    );
    ok = false;
  }
  final figures = f.get<List<Object>>('figures')?.cast<Figure>();
  if (abc == null &&
      figures != null &&
      !_figuresFit(figures, time ?? '4/4', f, issues)) {
    ok = false;
  }
  if (!ok) return null;
  return RhythmSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    time: time ?? '4/4',
    bpm: f.get<int>('bpm') ?? 80,
    note: f.get<Pitch>('note') ?? Pitch.parse('C4'),
    figures: figures,
    measures: figures == null ? null : (f.get<int>('measures') ?? 4),
    abc: abc,
  );
}

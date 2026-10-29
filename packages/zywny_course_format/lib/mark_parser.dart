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
    firstLine: mark.bodyLine,
    blockLine: mark.line,
    where: where,
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
  text: f.get<String>('chart'),
  progression: f.get<String>('progression'),
  key: f.get<String>('key') ?? 'C',
  time: f.get<String>('time') ?? '4/4',
  textLine: f.lineOf('chart'),
  progressionLine: f.lineOf('progression'),
  issues: issues,
);

/// A grade de uma marca ou de um exercício: o nome da progressão da biblioteca,
/// ou o texto lido pelo leitor do EX09 (cada erro sai com a coluna).
bool _gradeOf({
  required String? text,
  required String? progression,
  required String key,
  required String time,
  required int textLine,
  required int progressionLine,
  required FileIssues issues,
}) {
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
        type == ExerciseType.playChart ||
        ((type == ExerciseType.playScore || type == ExerciseType.playPattern) &&
            f.get<String>('mode') == 'realtime'),
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
  legato: pass?.get<int>('legato'),
  staccato: pass?.get<int>('staccato'),
  dynamics: pass?.get<bool>('dynamics') ?? false,
  balance: pass?.get<int>('balance'),
  pedal: pass?.get<int>('pedal'),
  steadiness: pass?.get<int>('steadiness'),
  swing: pass?.get<(int, int)>('swing'),
  accents: pass?.get<int>('accents'),
  choruses: pass?.get<int>('choruses'),
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
    } else if (rule.realtimeOnly && !realtime) {
      issues.error(
        pass.lineOf(key),
        key == 'speed'
            ? 'o modo espera não tem andamento: tire `speed` ou use '
                  '`mode: realtime`.'
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

/// `notes` como [NotesSpec]; confere faixa, `only` e quantidade. [letters]
/// e [naturalsOnly] valem para o `name-note`. [key] lê outra chave com a
/// mesma sintaxe (o `roots` do `listen-chord`).
NotesSpec? _notes(
  Fields f,
  FileIssues issues, {
  required int defaultCount,
  bool naturalsOnly = false,
  List<String>? letters,
  String key = 'notes',
}) {
  final raw = f.values[key];
  final line = f.lineOf(key);
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
      final keys = _keyChoice(f);
      final cycle = _enumOf(KeyCycle.values, f.get<String>('cycle'));
      if (!_keyRules(f, issues)) return null;
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
        keys: keys,
        cycle: cycle,
        keyStart:
            _enumOf(KeyStart.values, f.get<String>('key-start')) ??
            KeyStart.written,
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
    case ExerciseType.listenNote:
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
              defaultCount: 10,
              naturalsOnly: true,
              letters: choices,
            )
          : _notes(f, issues, defaultCount: 10);
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
            _enumOf(OctaveRule.values, f.get<String>('octave')) ??
            OctaveRule.any,
        choices: choices,
        key: f.get<String>('key'),
      );
    case ExerciseType.listenInterval:
      final notes = _notes(f, issues, defaultCount: 10);
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
          issues.error(
            f.lineOf('intervals'),
            '`intervals` repete um intervalo.',
          );
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
    case ExerciseType.listenScore:
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
          _enumOf(ScoreChange.values, f.get<String>('change')) ??
          ScoreChange.pitch;
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
    case ExerciseType.playChord:
      return _playChord(f, id, title, line, pass, issues);
    case ExerciseType.playPattern:
      return _playPattern(f, id, title, line, pass, issues);
    case ExerciseType.playChart:
      return _playChart(f, id, title, line, pass, issues);
    case ExerciseType.listenChord:
      return _listenChord(f, id, title, line, pass, issues);
    case ExerciseType.listenGroove:
      return _listenGroove(f, id, title, line, pass, issues);
    case ExerciseType.echo:
      return _echo(f, id, title, line, pass, issues);
    case ExerciseType.listenProgression:
      return _listenProgression(f, id, title, line, pass, issues);
    case ExerciseType.harmonize:
      return _harmonize(f, id, title, line, pass, issues);
  }
}

/// `play-chord` (EX02): as cifras, a inversão, o molde, a mão e a faixa. Os
/// erros de cifra, de grau, de inversão e de molde saem já na leitura, com a
/// linha da chave ou do item.
/// `play-pattern` (EX06): o padrão, o tom (`key:`, ou `keys:` e `cycle:` como
/// no `play-score`), a mão e as variações. Chave que só vale com outro padrão é
/// erro; `fingering: true` num padrão sem dedilhado só avisa.
PlayPatternSpec? _playPattern(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  final pattern = _enumOf(PatternKind.values, f.get<String>('pattern'))!;
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
  // O arpejo de 3-5-7-9 (o jazz) é de uma oitava só: a descida é 7 5 3 1.
  if (f.get<String>('chord') == '3-5-7-9' && (f.get<int>('octaves') ?? 1) > 1) {
    issues.error(
      f.lineOf('octaves'),
      '`chord: 3-5-7-9` vai só até uma oitava (a descida é 7 5 3 1).',
    );
    ok = false;
  }
  if (!ok) return null;

  final scale = _scaleOf(f.get<String>('scale'));
  final keys = _keyChoice(f);
  final cycle = _enumOf(KeyCycle.values, f.get<String>('cycle'));
  final key = f.get<String>('key') ?? 'C';
  final octaves = f.get<int>('octaves') ?? 1;
  if (f.has('fingering') && (f.get<bool>('fingering') ?? true)) {
    final gap = f.get<String>('hand') == 'contrary'
        ? 'sem dedilhado na mão contrária: o livro não traz. '
              'Use `fingering: false` para calar o aviso.'
        : _fingeringGap(
            pattern,
            scale,
            f.get<String>('chord') ?? 'M',
            key,
            keys,
            cycle,
            octaves,
          );
    if (gap != null) issues.warning(f.lineOf('fingering'), gap);
  }
  return PlayPatternSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    pattern: pattern,
    scale: scale,
    chord: f.get<String>('chord') ?? 'M',
    chords:
        _enumOf(PatternChords.values, f.get<String>('chords')) ??
        PatternChords.triads,
    style:
        _enumOf(PatternStyle.values, f.get<String>('style')) ??
        PatternStyle.block,
    figure:
        _enumOf(PatternFigure.values, f.get<String>('figure')) ??
        PatternFigure.figure1353,
    order:
        _enumOf(PatternOrder.values, f.get<String>('order')) ??
        PatternOrder.order123,
    source:
        _enumOf(PatternSource.values, f.get<String>('source')) ??
        PatternSource.scale,
    motif: motif,
    key: key,
    keys: keys,
    cycle: cycle,
    keyStart:
        _enumOf(KeyStart.values, f.get<String>('key-start')) ??
        KeyStart.written,
    octaves: octaves,
    direction:
        _enumOf(PatternDirection.values, f.get<String>('direction')) ??
        PatternDirection.upDown,
    hand:
        _enumOf(PatternHand.values, f.get<String>('hand')) ?? PatternHand.right,
    fingering: f.get<bool>('fingering') ?? true,
    articulation:
        _enumOf(PatternArticulation.values, f.get<String>('articulation')) ??
        PatternArticulation.legato,
    grouping:
        _enumOf(PatternGrouping.values, f.get<String>('grouping')) ??
        PatternGrouping.two,
    mode: _enumOf(PlayMode.values, f.get<String>('mode')) ?? PlayMode.wait,
    bpm: f.get<int>('bpm'),
  );
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

/// O aviso de `fingering: true` num padrão sem dedilhado, ou `null` quando o
/// livro traz. Com vários tons (`keys:`, `cycle:`), basta um tom fora da tabela
/// para avisar.
String? _fingeringGap(
  PatternKind pattern,
  ScaleKind scale,
  String chord,
  String key,
  KeyChoice? keys,
  KeyCycle? cycle,
  int octaves,
) {
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
      return _hasTable(pattern, scale, key, octaves) ? null : none;
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

PlayChordSpec? _playChord(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  final chords = _chords(f, issues);
  if (chords == null) return null;
  final samples = chords.samples;
  final rawInversion = f.values['inversion'];
  final inversions = rawInversion is List
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
  final voicing = f.get<String>('voicing');
  final hand =
      _enumOf(ChordHand.values, f.get<String>('hand')) ?? ChordHand.any;
  var ok = true;
  if (inversions.contains(ChordInversionChoice.third) &&
      samples.any((sample) => sample.seventh == null)) {
    issues.error(
      f.lineOf('inversion'),
      'tríade não tem 3ª inversão: `third` pede uma cifra de sétima.',
    );
    ok = false;
  }
  if (voicing != null) {
    final shape = kVoicingShapes[voicing]!;
    if (inversions.any((i) => i != ChordInversionChoice.any)) {
      issues.error(
        f.lineOf('voicing'),
        'o molde já decide a ordem das notas; tire `inversion`.',
      );
      ok = false;
    }
    for (final sample in samples) {
      try {
        buildVoicing(sample, shape: shape, lowest: 36, highest: 96);
      } on ArgumentError {
        issues.error(
          f.lineOf('voicing'),
          '`$voicing` não cabe em `${sample.label(ChordNotation.american)}`.',
        );
        ok = false;
        break;
      }
    }
    if (hand == ChordHand.left &&
        const {'so-what', 'upper-triad', 'block'}.contains(voicing)) {
      issues.warning(
        f.lineOf('hand'),
        '`$voicing` pede as duas mãos; com `hand: left` o acorde inteiro '
        'fica na esquerda.',
      );
    }
  }
  final rangeText = f.get<String>('range');
  NoteRange? range;
  if (rangeText != null) {
    range = NoteRange.tryParse(rangeText);
    if (range == null) {
      issues.error(
        f.lineOf('range'),
        '`$rangeText` não é uma faixa de notas: escreva da mais grave para a '
        'mais aguda, como C3-C6.',
      );
      ok = false;
    }
  }
  // EX03: o modo com tempo. O `bpm` marca cada pergunta, então não vale junto
  // com o `time-limit` (que também marca o fim de cada pergunta).
  final bpm = f.get<int>('bpm');
  if (bpm == null && f.has('beats')) {
    issues.error(
      f.lineOf('beats'),
      '`beats` só vale com `bpm`: o tempo de cada acorde vem do andamento.',
    );
    ok = false;
  }
  if (bpm != null && pass?.get<int>('time-limit') != null) {
    issues.error(
      f.lineOf('bpm'),
      '`bpm` e `time-limit` não valem juntos: o metrônomo já marca o fim de '
      'cada pergunta.',
    );
    ok = false;
  }
  if (!ok) return null;
  return PlayChordSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    chords: chords.spec,
    inversions: inversions,
    voicing: voicing,
    hand: hand,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    range: range,
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

/// `play-chart` (EX11): a grade (texto, ou a progressão da biblioteca com
/// `chart: {progression, key, bars}`), o molde (um nome da biblioteca, ou o
/// mapa `pattern: {grid, left, right}`), o andamento e o juiz. Um molde de
/// outro compasso que a grade é erro; `swing` pede colcheias no molde.
PlayChartSpec? _playChart(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
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
    text: text,
    progression: progression,
    key: key,
    time: time,
    textLine: f.lineOf('chart'),
    progressionLine: map?.lineOf('progression') ?? f.lineOf('chart'),
    issues: issues,
  )) {
    ok = false;
  }
  final pattern = _patternOf(f, issues);
  if (pattern == null) ok = false;
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
  final bpm = f.get<int>('bpm');
  if (bpm == null && f.has('beats')) {
    issues.error(f.lineOf('beats'), '`beats` não vale no `play-chart`.');
    ok = false;
  }
  final backing = pattern == null ? null : _backingOf(f, pattern, time, issues);
  if (f.has('backing') && backing == null) ok = false;
  if (!ok || pattern == null) return null;
  return PlayChartSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    chartText: text,
    progression: progression,
    progressionBars: map?.get<int>('bars'),
    key: key,
    time: time,
    pattern: pattern,
    bpm: bpm ?? 80,
    swing: swing,
    choruses: f.get<int>('choruses') ?? 1,
    voicing: f.get<String>('voicing'),
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    strict: f.get<bool>('strict') ?? true,
    omit5: f.get<bool>('omit5') ?? true,
    strictRhythm: f.get<bool>('strict-rhythm') ?? false,
    // Com a base, o metrônomo começa desligado (EX12).
    metronome: f.get<bool>('metronome') ?? backing == null,
    show: _enumOf(ChartShow.values, f.get<String>('show')) ?? ChartShow.chords,
    keys: _keyChoice(f),
    cycle: _enumOf(KeyCycle.values, f.get<String>('cycle')),
    keyStart:
        _enumOf(KeyStart.values, f.get<String>('key-start')) ??
        KeyStart.written,
    backing: backing,
  );
}

/// `backing:` do `play-chart` (EX12): `drums` (só a bateria, sem baixo) ou o
/// mapa `{style, drums, bass, volume, intro}`. Sem `style:`, é o estilo que
/// combina com o molde. `null` sem `backing:` ou com erro (o erro já saiu).
BackingSpec? _backingOf(
  Fields f,
  CompingPattern pattern,
  String time,
  FileIssues issues,
) {
  final raw = f.values['backing'];
  if (raw == null) return null;
  final map = raw is Fields ? raw : null;
  final name = map?.get<String>('style');
  final BackingStyle style;
  if (name == null) {
    style = backingStyleFor(pattern);
  } else {
    final named = backingStyleNamed(name);
    if (named == null) {
      final hint = suggestFor(name, backingStyleNames);
      issues.error(
        map!.lineOf('style'),
        'não há o estilo `$name` na tabela de estilos'
        '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
      );
      return null;
    }
    style = named;
  }
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
  var ok = true;
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
  if (leftBars == null || rightBars == null) {
    ok = false;
  } else if (leftBars.length != rightBars.length) {
    issues.error(
      map.lineOf('right'),
      '`left` tem ${leftBars.length} compasso(s) e `right` tem '
      '${rightBars.length}: as duas mãos têm de ter o mesmo.',
    );
    ok = false;
  }
  if (!ok) return null;
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
ListenChordSpec? _listenChord(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  final answer =
      _enumOf(ChordAnswerKind.values, f.get<String>('answer')) ??
      ChordAnswerKind.quality;
  final isFunction = answer == ChordAnswerKind.function;
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
  final count = f.get<int>('count') ?? 10;

  var qualities = <String>[];
  NotesSpec? roots;
  if (!isFunction) {
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
        issues.error(
          f.lineOf('qualities'),
          '`qualities` repete uma qualidade.',
        );
        ok = false;
      }
    } else {
      issues.error(
        line,
        '`answer: quality` pede `qualities`: as qualidades que os botões mostram.',
      );
      ok = false;
    }
    if (f.has('roots')) {
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
      roots = _notes(f, issues, defaultCount: count, key: 'roots');
      if (roots == null) ok = false;
    } else {
      roots = RandomNotes(
        range: NoteRange(Pitch.parse('C3'), Pitch.parse('G4')),
        count: count,
      );
    }
  }

  var degrees = <String>[];
  if (isFunction) {
    degrees =
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
  }
  if (!ok) return null;
  return ListenChordSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
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

/// As cifras de `chords:` já lidas e conferidas, com um [ChordSymbol] de
/// amostra por cifra (a do sorteio tem a raiz em dó), para as regras de
/// inversão e de molde.
typedef _Chords = ({ChordsSpec spec, List<ChordSymbol> samples});

/// `chords:` do `play-chord`: a lista fixa ou o sorteio. `null` se alguma
/// cifra, qualidade ou grau está errada (o erro já foi dado).
_Chords? _chords(Fields f, FileIssues issues) {
  final raw = f.values['chords'];
  if (raw is List) {
    final symbols = raw.cast<String>();
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

  final map = raw as Fields;
  final qualities = map.get<List<Object>>('qualities')?.cast<String>();
  final degrees = map.get<List<Object>>('degrees')?.cast<String>();
  if ((qualities == null) == (degrees == null)) {
    issues.error(
      f.lineOf('chords'),
      qualities == null
          ? 'falta `qualities` ou `degrees` em `chords`.'
          : 'use `qualities` **ou** `degrees`, não os dois.',
    );
    return null;
  }
  final samples = <ChordSymbol>[];
  var ok = true;
  if (qualities != null) {
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
  }
  if (degrees != null) {
    const dOfC = KeySpec(tonic: 0, minor: false, spelling: 'C');
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
  }
  if (!ok) return null;

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
  final rawRoots = map.values['roots'];
  final roots = switch (rawRoots) {
    List() => rawRoots.cast<String>(),
    String() when rawRoots != 'random' && rawRoots != 'white' => [rawRoots],
    _ => null,
  };
  return (
    spec: RandomChords(
      qualities: qualities,
      count: count,
      sequence: sequence,
      roots: roots,
      whiteOnly: rawRoots == 'white',
      key: key,
    ),
    samples: samples,
  );
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
  final grooveName = f.get<String>('groove');
  final groove = grooveName == null ? null : rhythmGrooveNamed(grooveName);
  // Com um groove ou um molde escrito (`right`), o ritmo é o molde: não há
  // sorteio nem ABC.
  final molde = groove != null || f.has('right');
  var ok = true;
  if (f.has('groove') && (f.has('right') || f.has('left'))) {
    issues.error(
      f.lineOf('groove'),
      '`groove` não vale com `right` e `left`: o groove já traz os moldes.',
    );
    ok = false;
  }
  if (molde) {
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
  } else if (abc != null) {
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
  } else if (!f.has('figures') && !f.has('left')) {
    issues.error(
      f.blockLine,
      'informe `figures` (ritmo sorteado), `abc` (ritmo escrito), `groove` ou '
      '`right` (molde).',
    );
    ok = false;
  }
  // O compasso: o do groove (que o exercício tem de repetir), ou 4/4.
  final effective = time ?? groove?.time ?? '4/4';
  if (groove != null && time != null && time != groove.time) {
    issues.error(
      f.lineOf('time'),
      'o groove `${groove.name}` é de ${groove.time}, e o exercício é de '
      '$time.',
    );
    ok = false;
  }
  final figures = molde ? null : f.get<List<Object>>('figures')?.cast<Figure>();
  if (abc == null &&
      figures != null &&
      !_figuresFit(figures, effective, f, issues)) {
    ok = false;
  }

  // `hands`: o groove diz as mãos que toca; sem groove, duas mãos são as que
  // têm `left:`, e `hands: two` sem `left:` é erro.
  final handsName = f.get<String>('hands');
  var hands = 1;
  if (groove != null) {
    hands = groove.hands;
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
  } else {
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
    hands = twoHands ? 2 : 1;
  }
  if (f.has('split') && hands != 2) {
    issues.error(
      f.lineOf('split'),
      '`split` só vale com duas mãos (`hands: two`, ou um `groove` de duas '
      'mãos).',
    );
    ok = false;
  }

  // Os moldes: os do groove, ou os escritos (`right`, e `left` se tiver).
  List<List<RhythmSymbol>>? right;
  List<List<RhythmSymbol>>? left;
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
  if (right != null && left != null && right.length != left.length) {
    issues.error(
      f.lineOf('left'),
      '`left` tem ${left.length} compasso(s) e `right` tem ${right.length}: as '
      'duas mãos têm de ter o mesmo número de compassos.',
    );
    ok = false;
  }

  // `measures` conta os compassos do exercício (4 por padrão), e o molde se
  // repete até fechá-los: tem de ser múltiplo dos compassos do molde.
  var measures = figures == null ? null : (f.get<int>('measures') ?? 4);
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

  if (!ok) return null;
  return RhythmSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    time: effective,
    bpm: f.get<int>('bpm') ?? 80,
    note: f.get<Pitch>('note') ?? Pitch.parse('C4'),
    figures: figures,
    measures: measures,
    abc: abc,
    hands: hands,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    groove: groove,
    right: right,
    left: left,
  );
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
ListenGrooveSpec? _listenGroove(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
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
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  final answer =
      _enumOf(ProgressionAnswer.values, f.get<String>('answer')) ??
      ProgressionAnswer.choice;
  final given = f.get<List<Object>>('progressions')!.cast<String>();
  var ok = true;
  if (answer == ProgressionAnswer.choice && given.length < 2) {
    issues.error(
      f.lineOf('progressions'),
      '`answer: choice` pede duas ou mais progressões: os botões escolhem entre elas.',
    );
    ok = false;
  }
  final charts = <String>[];
  final spelled = <String>{};
  for (final (i, text) in given.indexed) {
    final chart = progressionNamed(text)?.chart ?? text;
    String? detail;
    final bars = parseProgression(chart, error: (m) => detail = m);
    if (bars == null) {
      final hint = suggestFor(text, [for (final p in kProgressions) p.name]);
      issues.error(
        _itemLine(f, 'progressions', i),
        '`$text` não é uma progressão da biblioteca'
        '${hint != null ? ' — você quis dizer `$hint`?' : ''}, nem uma grade '
        'escrita${detail != null ? ' ($detail)' : ''}: escreva os graus '
        'separados por espaço e os compassos por `|`, como `I | vi | ii V | I`.',
      );
      ok = false;
      continue;
    }
    final chords = bars.fold<int>(0, (sum, bar) => sum + bar.length);
    if (chords > 8) {
      issues.error(
        _itemLine(f, 'progressions', i),
        '`$text` tem $chords acordes: o máximo é 8 (é longo demais para o ouvido).',
      );
      ok = false;
      continue;
    }
    final degrees = [
      for (final bar in bars)
        for (final degree in bar) degree.label,
    ].join(' ');
    if (!spelled.add(degrees)) {
      issues.error(
        _itemLine(f, 'progressions', i),
        '`$text` tem os mesmos graus de uma progressão anterior.',
      );
      ok = false;
      continue;
    }
    charts.add(chart);
  }
  final styleName = f.get<String>('style') ?? 'block';
  BackingStyle? style;
  if (styleName != 'block') {
    style = backingStyleNamed(styleName);
    if (style != null && style.time != '4/4') {
      issues.error(
        f.lineOf('style'),
        'o estilo `${style.name}` é de ${style.time}, e a progressão é em 4/4.',
      );
      ok = false;
    }
  }
  if (!ok) return null;
  return ListenProgressionSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    answer: answer,
    progressions: charts,
    key: f.get<String>('key') ?? 'C',
    style: style,
    bpm: f.get<int>('bpm') ?? 90,
    count: f.get<int>('count') ?? 8,
  );
}

/// `harmonize` (EX16): o modo, a melodia (`step` gerada ou `file` do autor), os
/// graus que o acorde pode ser, onde ele troca e o molde. O que depende da nota
/// (se um acorde cabe no compasso, a fórmula da melodia) é do app, que lê a
/// melodia. `null` com erro (o erro já saiu).
HarmonizeSpec? _harmonize(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  var ok = true;
  final mode =
      _enumOf(HarmonizeMode.values, f.get<String>('mode')) ??
      HarmonizeMode.play;
  // A rearmonização (nível 6) está no formato, mas ainda não roda.
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

  // Sem `melody:` a leitura da chave já disse o que falta.
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

  final change =
      _enumOf(HarmonizeChange.values, f.get<String>('change')) ??
      HarmonizeChange.bar;
  if (change == HarmonizeChange.marked && melody is StepMelody) {
    issues.error(
      f.lineOf('change'),
      '`change: marked` pede uma melodia do autor (`file`): a melodia gerada '
      'não tem marcas de troca.',
    );
    ok = false;
  }

  // O molde só vale com `play` e `by-ear`. `block` é o acorde na esquerda nos
  // tempos 1 e 3 (a direita é a melodia; ver o EX16); os outros são os do EX11.
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

  if (!ok) return null;
  return HarmonizeSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    mode: mode,
    melody: melody,
    chords: chords,
    change: change,
    pattern: mode == HarmonizeMode.degrees ? null : name,
    bpm: f.get<int>('bpm') ?? 70,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    count: f.get<int>('count') ?? 1,
  );
}

/// Os moldes que o `harmonize` aceita: `block` (o dele), `any` e os do EX11.
bool _harmonizePattern(String name) =>
    name == 'block' || name == 'any' || compingPatternNamed(name) != null;

/// `echo` (EX14): a fonte das notas (`source:`, uma das três formas), a faixa, o
/// tamanho e o andamento das frases, e a conferência (`octave`, `rhythm`, a mão).
/// `null` com erro (o erro já saiu).
EchoSpec? _echo(
  Fields f,
  String id,
  String title,
  int line,
  Fields? pass,
  FileIssues issues,
) {
  var ok = true;
  final map = f.values['source'] as Fields?;
  // Sem `source:` a leitura do campo obrigatório já disse o que falta.
  if (map == null) return null;
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
  if (licks != null) {
    for (final key in ['notes', 'figures', 'leaps', 'start']) {
      if (!f.has(key)) continue;
      issues.error(
        f.lineOf(key),
        '`$key` não vale com `licks`: a frase vem da biblioteca.',
      );
      ok = false;
    }
  }
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
        text: chartText,
        progression: progression,
        key: chartKey,
        time: '4/4',
        textLine: f.lineOf('chart'),
        progressionLine: chartMap?.lineOf('progression') ?? f.lineOf('chart'),
        issues: issues,
      )) {
    ok = false;
  }
  final backing = _echoBacking(f, issues);
  if (f.has('backing') && backing == null) ok = false;
  if (!ok || range == null) return null;
  return EchoSpec(
    id: id,
    title: title,
    pass: _pass(pass),
    line: line,
    source: source,
    range: range,
    notes: f.get<int>('notes') ?? 4,
    figures: f.get<List<Object>>('figures')?.cast<Figure>() ?? [Figure.quarter],
    measures: f.get<int>('measures') ?? 1,
    leaps: f.get<int>('leaps') ?? 3,
    start: _enumOf(EchoStart.values, f.get<String>('start')) ?? EchoStart.tonic,
    bpm: f.get<int>('bpm') ?? 80,
    swing: f.get<int>('swing') ?? 50,
    count: f.get<int>('count') ?? 8,
    octave:
        _enumOf(EchoOctave.values, f.get<String>('octave')) ?? EchoOctave.any,
    transpose:
        _enumOf(EchoTranspose.values, f.get<String>('transpose')) ??
        EchoTranspose.none,
    rhythm:
        _enumOf(EchoRhythm.values, f.get<String>('rhythm')) ?? EchoRhythm.loose,
    split: f.get<Pitch>('split') ?? Pitch.parse('C4'),
    hand: f.get<String>('hand') == 'left' ? HandChoice.left : HandChoice.right,
    backing: backing,
    chartText: chartText,
    progression: progression,
    progressionBars: chartMap?.get<int>('bars'),
    chartKey: chartKey,
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

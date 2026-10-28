import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_course_format/directory_course_files.dart';
import 'package:zywny_course_format/lesson_scanner.dart';
import 'package:zywny_music/note_name.dart';

const _course = '''---
format: 1
id: t
title: T
author: a
version: "1"
lessons: [um]
---

Oi.
''';

String _lesson(String body, {String front = ''}) =>
    '---\nid: um\ntitle: Um\n$front---\n\n$body';

Future<CourseReadResult> _read(String body, {String front = ''}) => readCourse(
  MemoryCourseFiles({
    'course.md': _course,
    'lessons/01-um.md': _lesson(body, front: front),
  }),
);

List<String> _messages(CourseReadResult result) => [
  for (final issue in result.issues) issue.toString(),
];

void main() {
  group('Pitch e NoteRange', () {
    test('lê notas em notação científica', () {
      final c4 = Pitch.parse('C4');
      expect((c4.midi, c4.alter, c4.octave), (60, 0, 4));
      expect(Pitch.parse('F#4').midi, 66);
      expect(Pitch.parse('Bb3').midi, 58);
      expect(Pitch.parse('A0').midi, 21);
      expect(Pitch.parse('C8').midi, 108);
    });

    test('recusa o que não é nota, com mensagem legível', () {
      for (final text in ['H4', 'C', 'c4', 'F##4', 'C9', 'G#0', '4C', '']) {
        expect(Pitch.tryParse(text), isNull, reason: text);
      }
      expect(
        () => Pitch.parse('H4'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith(
              '`H4` não é uma nota: use de C a B, com # ou b, e a '
              'oitava, como C4',
            ),
          ),
        ),
      );
    });

    test('linha ou espaço, igual nas duas claves', () {
      // Treble: E4 G4 B4 D5 F5 são linhas. Baixo: G2 B2 D3 F3 A3.
      for (final line in ['E4', 'G4', 'B4', 'D5', 'F5', 'G2', 'B2', 'D3']) {
        expect(Pitch.parse(line).onLine, isTrue, reason: line);
      }
      for (final space in ['F4', 'A4', 'C5', 'E5', 'A2', 'C3', 'E3', 'G3']) {
        expect(Pitch.parse(space).onLine, isFalse, reason: space);
      }
      expect(Pitch.parse('C4').onLine, isTrue); // linha suplementar
    });

    test('faixa inclusiva e naturais', () {
      final range = NoteRange.parse('C4-G4');
      expect(range.contains(Pitch.parse('C4')), isTrue);
      expect(range.contains(Pitch.parse('G4')), isTrue);
      expect(range.contains(Pitch.parse('A4')), isFalse);
      expect(
        [for (final p in range.naturals) '$p'],
        [
          'C4', 'D4', 'E4', 'F4', 'G4', //
        ],
      );
      expect(NoteRange.tryParse('G4-C4'), isNull);
      expect(NoteRange.tryParse('C4'), isNull);
    });
  });

  group('lesson_scanner', () {
    test('marca dentro de bloco de código de exemplo não vira marca', () {
      final scanned = scanLessonFile(
        '---\nid: a\n---\n'
        '````markdown\n```zywny-score\nabc: C\n```\n````\n\n'
        '~~~\n```zywny-audio\n~~~\n\n'
        '```zywny-keyboard\nfrom: C4\n```\n',
        onError: (line, message) => fail('$line $message'),
      );
      final marks = scanned.segments.whereType<MarkSegment>().toList();
      expect([for (final m in marks) m.name], ['keyboard']);
      expect(marks.single.line, 14);
      expect(scanned.segments.whereType<TextSegment>(), hasLength(1));
    });

    test('a marca guarda a linha em que abre', () {
      final scanned = scanLessonFile(
        '---\nid: a\n---\nTexto\n\n```zywny-audio\nfile: x\n```\n',
        onError: (line, message) => fail('$line $message'),
      );
      expect(scanned.front!.firstLine, 2);
      final texts = scanned.segments.whereType<TextSegment>();
      expect(texts.single.line, 4);
      final mark = scanned.segments.whereType<MarkSegment>().single;
      expect((mark.line, mark.bodyLine, mark.body), (6, 7, 'file: x'));
    });

    test('crases com letra grudada não abrem marca', () {
      final errors = <String>[];
      final scanned = scanLessonFile(
        '---\nid: a\n---\n```zywny-score extra\nabc: C\n```\n',
        onError: (line, message) => errors.add('$line $message'),
      );
      // Não é a abertura exata: vira cerca comum.
      expect(scanned.segments.whereType<MarkSegment>(), isEmpty);
      expect(errors, isEmpty);
    });
  });

  group('readCourse', () {
    test('o curso mínimo vira o modelo esperado', () async {
      final result = await readCourse(
        DirectoryCourseFiles(Directory('../../test/fixtures/cursos/minimo')),
      );
      expect(result.issues, isEmpty);
      final course = result.course!;
      expect(course.id, 'minimo');
      expect(course.version, '1'); // número no arquivo, texto no modelo
      expect(course.format, 1);
      expect(course.intro, contains('duas lições'));
      expect([for (final l in course.lessons) l.id], ['o-teclado', 'pauta']);
      expect(course.lessons[1].requires, ['o-teclado']);

      final first = course.lessons.first.blocks;
      expect(first.whereType<ExerciseMark>(), isEmpty);
      final keyboard = first.whereType<KeyboardMark>().single;
      expect((keyboard.from.toString(), keyboard.to.toString()), ('C4', 'C5'));
      expect(keyboard.mark.single.toString(), 'C4');
      expect(keyboard.caption, 'O dó central');
      expect(keyboard.names, isFalse);
      expect(
        (first.last as TextBlock).markdown,
        contains('zywny-exercise'), // o exemplo ficou como texto
      );

      final exercise = course.lessons[1].exercises.single as PlayNotesSpec;
      expect(exercise.id, 'ler-do-ao-sol');
      expect(exercise.type, ExerciseType.playNotes);
      expect(exercise.clef, Clef.treble);
      expect(exercise.accidentals, Accidentals.none);
      final notes = exercise.notes as RandomNotes;
      expect((notes.range.toString(), notes.count), ('C4-G4', 12));
      expect(notes.only, isNull);
      expect(exercise.pass.accuracy, 90);
      expect(exercise.pass.rounds, 1);
      expect(exercise.pass.speed, 100);
      expect(exercise.pass.timeLimit, isNull);
      expect(exercise.line, 9);
    });

    test('lê um zip como lê uma pasta', () async {
      final archive = Archive()
        ..add(ArchiveFile.string('course.md', _course))
        ..add(ArchiveFile.string('lessons/01-um.md', _lesson('Texto.\n')));
      final bytes = ZipEncoder().encodeBytes(archive);
      final result = await readCourse(ZipCourseFiles(bytes));
      expect(result.issues, isEmpty);
      expect(result.course!.lessons.single.id, 'um');
    });

    test('todos os tipos de exercício, com os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: find-key
title: A
notes: [C4, D4]
```

```zywny-exercise
id: b
type: name-note
title: B
notes: {random: C4-G4, only: spaces}
choices: [D, F, A, C, E, G]
pass: {time-limit: 5}
```

```zywny-exercise
id: c
type: rhythm
title: C
figures: [quarter, eighth, quarter-rest]
pass: {speed: 80}
```

```zywny-exercise
id: d
type: count-beats
title: D
time: 6/8
figures: [eighth, dotted-quarter]
```

```zywny-exercise
id: e
type: play-score
title: E
abc: |
  X:1
  K:C
  CDEF|
hand: left
mode: realtime
measures: "2-3"
bpm: 60
pass: {speed: 75, accuracy: 85, rounds: 2}
```

```zywny-exercise
id: f
type: choice
title: F
question: Quanto vale?
options: [1, 2, 4]
answer: 2
abc: "C"
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final find = specs[0] as FindKeySpec;
      expect(find.octave, OctaveRule.any);
      expect((find.notes as FixedNotes).notes, hasLength(2));
      final name = specs[1] as NameNoteSpec;
      expect((name.notes as RandomNotes).only, OnlyOn.spaces);
      expect(name.choices, ['D', 'F', 'A', 'C', 'E', 'G']);
      expect(name.pass.timeLimit, 5);
      final rhythm = specs[2] as RhythmSpec;
      expect((rhythm.time, rhythm.bpm, rhythm.measures), ('4/4', 80, 4));
      expect(rhythm.note.toString(), 'C4');
      expect(rhythm.figures, [
        Figure.quarter,
        Figure.eighth,
        Figure.quarterRest,
      ]);
      expect(rhythm.pass.speed, 80);
      final count = specs[3] as CountBeatsSpec;
      expect((count.time, count.count), ('6/8', 8));
      final score = specs[4] as PlayScoreSpec;
      expect(score.hand, HandChoice.left);
      expect(score.mode, PlayMode.realtime);
      expect(score.measures.toString(), '2-3');
      expect((score.bpm, score.pass.speed, score.pass.rounds), (60, 75, 2));
      expect((score.source as AbcSource).isComplete, isTrue);
      final choice = specs[5] as ChoiceSpec;
      expect(choice.options, ['1', '2', '4']);
      expect(choice.answer, 1);
    });

    test('sorteio com `only` precisa de pelo menos duas notas', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: play-notes
title: A
notes: {random: C4-D4, only: lines}
```
''');
      expect(_messages(result), [
        'lessons/01-um.md:10: erro: a faixa C4-D4 tem 1 nota em linha: com '
            '`only: lines` o sorteio precisa de pelo menos duas.',
      ]);
      expect(result.course, isNull);
    });

    test('name-note precisa de botão para cada nota sorteada', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: name-note
title: A
notes: {random: C4-E4}
choices: [C, D]
```
''');
      expect(_messages(result).single, contains('E, que não tem botão'));
    });

    test('listen-note lê as chaves e põe os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: l1-ouvir-achar
type: listen-note
title: Ouça e ache a tecla
notes: {random: C4-B4, count: 8}
reference: C4
input: keyboard
octave: any
pass: {accuracy: 60}
```

```zywny-exercise
id: b
type: listen-note
title: B
notes: [C4]
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final achar = specs[0] as ListenNoteSpec;
      expect(achar.type, ExerciseType.listenNote);
      expect(achar.input, AnswerInput.keyboard);
      expect(achar.octave, OctaveRule.any);
      expect(achar.reference.toString(), 'C4');
      expect(achar.pass.accuracy, 60);
      final sorteio = achar.notes as RandomNotes;
      expect((sorteio.range.toString(), sorteio.count), ('C4-B4', 8));

      final padroes = specs[1] as ListenNoteSpec;
      expect(padroes.input, AnswerInput.keyboard);
      expect(padroes.octave, OctaveRule.any);
      expect(padroes.reference, isNull);
      expect(padroes.key, isNull);
      expect(padroes.choices, ['C', 'D', 'E', 'F', 'G', 'A', 'B']);
      expect(padroes.notes, isA<FixedNotes>());
    });

    test('listen-note: `octave` e `key` não valem com botões', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-note
title: A
notes: {random: C4-E4}
input: buttons
octave: exact
choices: [C, D, E]
```
''');
      expect(
        _messages(result).single,
        contains('`octave` só vale com `input: keyboard`'),
      );
      expect(result.course, isNull);
    });

    test('listen-note: `choices` não vale com teclado', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-note
title: A
notes: {random: C4-E4}
input: keyboard
choices: [C, D]
```
''');
      expect(
        _messages(result).single,
        contains('`choices` só vale com `input: buttons`'),
      );
    });

    test('listen-note com botões exige um botão para cada nota', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-note
title: A
notes: {random: C4-E4}
input: buttons
choices: [C, D]
```
''');
      expect(_messages(result).single, contains('E, que não tem botão'));
    });

    test('listen-score lê as chaves e põe os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: l6-onde-mudou-ritmo
type: listen-score
title: Onde o ritmo mudou
step: 4c
change: rhythm
answer: measure
count: 5
pass: {accuracy: 60}
```

```zywny-exercise
id: l2-igual-ou-diferente
type: listen-score
title: Igual ou diferente
step: 1c
answer: same-different
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final ritmo = specs[0] as ListenScoreSpec;
      expect(ritmo.type, ExerciseType.listenScore);
      expect(ritmo.step, '4c');
      expect(ritmo.change, ScoreChange.rhythm);
      expect(ritmo.answer, ScoreAnswer.measure);
      expect(ritmo.count, 5);
      expect(ritmo.bpm, isNull);

      final igual = specs[1] as ListenScoreSpec;
      expect(igual.change, ScoreChange.pitch);
      expect(igual.answer, ScoreAnswer.sameDifferent);
      expect(igual.count, 5);
    });

    test('listen-score: passo que não existe', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: listen-score
title: X
step: 101a
```
''');
      expect(_messages(result).single, contains('não é um passo'));
    });

    test('listen-score: o nome vai de 1a a 100d', () async {
      for (final (step, ok) in [
        ('1a', true),
        ('57c', true),
        ('100d', true),
        ('101a', false),
        ('0a', false),
        ('21e', false),
      ]) {
        final result = await _read('''
```zywny-exercise
id: x
type: listen-score
title: X
step: $step
```
''');
        expect(
          _messages(result).where((m) => m.contains('não é um passo')),
          ok ? isEmpty : hasLength(1),
          reason: step,
        );
      }
    });

    test('listen-score: accidental pede um passo com armadura', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: listen-score
title: X
step: 4c
change: accidental
```
''');
      expect(_messages(result).single, contains('do `11a` em diante'));
    });

    test('listen-score: note lê a resposta (E10)', () async {
      final result = await _read('''
```zywny-exercise
id: l10-onde-mudou
type: listen-score
title: Onde mudou, nas duas mãos
step: 5d
answer: note
count: 5
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as ListenScoreSpec;
      expect(spec.answer, ScoreAnswer.note);
      expect(spec.change, ScoreChange.pitch);
      expect(spec.count, 5);
    });

    test('listen-score: dictation lê a resposta', () async {
      final result = await _read('''
```zywny-exercise
id: l3-ditado
type: listen-score
title: Ditado de ouvido
step: 1c
answer: dictation
count: 2
pass: {accuracy: 60}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as ListenScoreSpec;
      expect(spec.answer, ScoreAnswer.dictation);
      expect(spec.count, 2);
    });

    test('listen-score: change não vale com dictation', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: listen-score
title: X
step: 1c
answer: dictation
change: rhythm
```
''');
      expect(
        _messages(result).single,
        contains('não vale com `answer: dictation`'),
      );
    });

    test('listen-interval lê as chaves e põe os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: l8-ouvir-tom
type: listen-interval
title: Meio tom ou tom?
notes: {random: C4-G4, count: 10}
intervals: [m2, M2]
pass: {accuracy: 70}
```

```zywny-exercise
id: l10-ouvir-juntas
type: listen-interval
title: Terça, quinta ou oitava
notes: {random: C4-C5, count: 10}
intervals: [M3, P5, P8]
direction: both
play: harmonic
pass: {accuracy: 70, time-limit: 20}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final tom = specs[0] as ListenIntervalSpec;
      expect(tom.type, ExerciseType.listenInterval);
      expect(tom.intervals, [IntervalName.m2, IntervalName.M2]);
      expect(tom.direction, IntervalDirection.up);
      expect(tom.play, IntervalPlay.melodic);
      expect(tom.pass.accuracy, 70);

      final juntas = specs[1] as ListenIntervalSpec;
      expect(juntas.intervals, [
        IntervalName.M3,
        IntervalName.P5,
        IntervalName.P8,
      ]);
      expect(juntas.direction, IntervalDirection.both);
      expect(juntas.play, IntervalPlay.harmonic);
      expect(juntas.pass.timeLimit, 20);
    });

    test('listen-interval: nome de intervalo desconhecido', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-interval
title: A
notes: [C4]
intervals: [m2, X9]
```
''');
      expect(
        _messages(result).single,
        contains('`X9` não é um intervalo; use: m2, M2, m3'),
      );
      expect(result.course, isNull);
    });

    test('listen-interval: intervalo repetido', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-interval
title: A
notes: [C4]
intervals: [m2, m2]
```
''');
      expect(_messages(result).single, contains('repete'));
      expect(result.course, isNull);
    });

    test('listen-interval: pelo menos dois intervalos', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: listen-interval
title: A
notes: [C4]
intervals: [m2]
```
''');
      expect(_messages(result).single, contains('pelo menos 2 itens'));
    });

    // EX04: o listen-chord, a forma da qualidade e a de casa ou tensão.
    test('listen-chord lê as duas formas e põe os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: c1-qualidades
type: listen-chord
title: Maior ou menor?
qualities: [M, m]
roots: {random: C3-G4}
count: 10
play: arpeggio
pass: {accuracy: 80}
```

```zywny-exercise
id: c2-lista
type: listen-chord
title: Duas fundamentais
qualities: [M, m, 7]
roots: [C3, G3]
play: both
inversion: random
```

```zywny-exercise
id: c3-casa-ou-tensao
type: listen-chord
title: Casa ou tensão?
answer: function
key: random
degrees: [I, IV, V7/vi, vi]
count: 8
pass: {accuracy: 75, time-limit: 20}
```

```zywny-exercise
id: c4-padroes
type: listen-chord
title: Só a qualidade
qualities: [M, m]
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();

      final maiorOuMenor = specs[0] as ListenChordSpec;
      expect(maiorOuMenor.type, ExerciseType.listenChord);
      expect(maiorOuMenor.answer, ChordAnswerKind.quality);
      expect(maiorOuMenor.qualities, ['M', 'm']);
      expect(maiorOuMenor.roots, isA<RandomNotes>());
      expect((maiorOuMenor.roots! as RandomNotes).count, 10);
      expect(maiorOuMenor.count, 10);
      expect(maiorOuMenor.play, ChordPlay.arpeggio);
      expect(maiorOuMenor.inversion, ChordInversionChoice.root);
      expect(maiorOuMenor.pass.accuracy, 80);

      final duas = specs[1] as ListenChordSpec;
      expect(duas.roots, isA<FixedNotes>());
      expect((duas.roots! as FixedNotes).notes, hasLength(2));
      expect(duas.play, ChordPlay.both);
      expect(duas.inversion, ChordInversionChoice.random);

      final funcao = specs[2] as ListenChordSpec;
      expect(funcao.answer, ChordAnswerKind.function);
      expect(funcao.key, 'random');
      expect(funcao.degrees, ['I', 'IV', 'V7/vi', 'vi']);
      expect(funcao.count, 8);
      expect(funcao.roots, isNull);
      expect(funcao.qualities, isEmpty);
      expect(funcao.pass.timeLimit, 20);

      final padroes = specs[3] as ListenChordSpec;
      expect(padroes.key, 'C');
      expect(padroes.degrees, isEmpty);
      expect(padroes.count, 10);
      expect(padroes.play, ChordPlay.block);
    });

    test('listen-chord: a forma quality pede qualities', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
```
''');
      expect(
        _messages(result).single,
        contains('`answer: quality` pede `qualities`'),
      );
      expect(result.course, isNull);
    });

    test('listen-chord: qualities com menos de dois itens', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
qualities: [M]
```
''');
      expect(_messages(result).single, contains('pelo menos 2 itens'));
    });

    test('listen-chord: qualidade desconhecida, com sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
qualities: [M, mm]
```
''');
      expect(_messages(result).single, contains('qualidade `mm` desconhecida'));
      expect(result.course, isNull);
    });

    test('listen-chord: qualidade repetida', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
qualities: [M, M]
```
''');
      expect(_messages(result).single, contains('repete uma qualidade'));
    });

    test('listen-chord: chaves de uma forma não valem na outra', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
answer: function
qualities: [M, m]
```

```zywny-exercise
id: d
type: listen-chord
title: D
qualities: [M, m]
degrees: [I, V]
```
''');
      final messages = _messages(result).join('\n');
      expect(messages, contains('`qualities` não vale com `answer: function`'));
      expect(messages, contains('`degrees` não vale com `answer: quality`'));
      expect(result.course, isNull);
    });

    test(
      'listen-chord: grau que não é casa nem tensão, e grau inválido',
      () async {
        final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
answer: function
degrees: [I, I7, hello]
```
''');
        final messages = _messages(result).join('\n');
        expect(messages, contains('`I7` não é casa nem tensão'));
        expect(messages, contains('`hello` não é um grau'));
        expect(result.course, isNull);
      },
    );

    test('listen-chord: count não vale com roots em lista', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
qualities: [M, m]
roots: [C3, G3]
count: 5
```
''');
      expect(
        _messages(result).single,
        contains('`count` não vale com `roots` em lista'),
      );
    });

    test('listen-chord: count dentro do sorteio de roots', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: listen-chord
title: C
qualities: [M, m]
roots: {random: C3-G4, count: 4}
```
''');
      expect(_messages(result).single, contains('use o `count` da lição'));
    });

    test('avisos não impedem o curso', () async {
      final result = await _read('Um <b>negrito</b>.\n');
      expect(_messages(result), [
        'lessons/01-um.md:6: aviso: HTML não é interpretado e aparece como '
            'texto.',
      ]);
      expect(result.hasErrors, isFalse);
      expect(result.course, isNotNull);
    });

    test('número, `yes` e erro de tipo no front matter', () async {
      final result = await readCourse(
        MemoryCourseFiles({
          'course.md': _course.replaceFirst('version: "1"', 'version: yes'),
          'lessons/01-um.md': _lesson('A.\n'),
        }),
      );
      // `yes` no YAML 1.2 é texto: vira a versão "yes", sem erro.
      expect(result.course!.version, 'yes');
    });

    test('keyboard com names: yes é recusado (booleano exige true)', () async {
      final result = await _read('```zywny-keyboard\nnames: yes\n```\n');
      expect(_messages(result).single, contains('`true` ou `false`'));
    });

    test('chave desconhecida sem sugestão lista as aceitas', () async {
      final result = await _read('```zywny-audio\nfile: x\nzzzzzz: 1\n```\n');
      final line = _messages(result).firstWhere((m) => m.contains('zzzzzz'));
      expect(line, contains('chaves aceitas na marca `zywny-audio`'));
    });

    // EX05: o play-score transposto (`keys`, `cycle` e `key-start`).
    test('play-score lê keys (lista, all, random) e cycle', () async {
      final result = await _read('''
```zywny-exercise
id: n2-cinco-dedos
type: play-score
title: Cinco dedos em vários tons
abc: |
  X:1
  L:1/4
  K:C
  CDEF|GFED|C4|]
keys: [C, G, D, F]
pass: {accuracy: 90, rounds: 4}
```

```zywny-exercise
id: n5-lick-ciclo
type: play-score
title: O lick pelo ciclo de quintas
abc: "CDEF|"
cycle: 5ths
key-start: rotate
mode: realtime
pass: {accuracy: 85, rounds: 10}
```

```zywny-exercise
id: n2-todos
type: play-score
title: Todos os tons
abc: "CDEF|"
keys: all
pass: {accuracy: 90}
```

```zywny-exercise
id: n2-sorteio
type: play-score
title: Um sorteado
abc: "CDEF|"
keys: random
pass: {accuracy: 90}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final fixed = specs[0] as PlayScoreSpec;
      expect((fixed.keys as FixedKeys).keys, ['C', 'G', 'D', 'F']);
      expect(fixed.cycle, isNull);
      expect(fixed.keyStart, KeyStart.written);
      final cycled = specs[1] as PlayScoreSpec;
      expect(cycled.keys, isNull);
      expect(cycled.cycle, KeyCycle.fifths);
      expect(cycled.keyStart, KeyStart.rotate);
      expect((specs[2] as PlayScoreSpec).keys, isA<AllKeys>());
      expect((specs[3] as PlayScoreSpec).keys, isA<RandomKeys>());
    });

    test('play-score sem keys nem cycle toca no tom escrito', () async {
      final result = await _read('''
```zywny-exercise
id: n1
type: play-score
title: Escrita
abc: "CDEF|"
```
''');
      final spec = result.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(spec.keys, isNull);
      expect(spec.cycle, isNull);
      expect(spec.keyStart, KeyStart.written);
    });

    test('play-score: tom que o formato não conhece, keys com cycle, '
        'key-start sem o que começar e com keys: random', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: play-score
title: A
abc: "CDEF|"
keys: [C, H]
```

```zywny-exercise
id: b
type: play-score
title: B
abc: "CDEF|"
keys: [C, G]
cycle: 4ths
```

```zywny-exercise
id: c
type: play-score
title: C
abc: "CDEF|"
key-start: rotate
```

```zywny-exercise
id: d
type: play-score
title: D
abc: "CDEF|"
keys: random
key-start: rotate
```
''');
      final messages = _messages(result);
      expect(messages, hasLength(4));
      expect(messages[0], contains('`keys` não é um tom que o formato conhece'));
      expect(messages[0], contains('(`H`)'));
      expect(messages[1], contains('`keys` e `cycle` não valem juntos'));
      expect(messages[2], contains('`key-start` só vale com `keys` ou `cycle`'));
      expect(messages[3], contains('`key-start` não vale com `keys: random`'));
    });

    test('play-score: key-start vale com uma lista de tons', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: play-score
title: A
abc: "CDEF|"
keys: [C, G, D]
key-start: rotate
```
''');
      expect(_messages(result), isEmpty);
      final spec = result.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(spec.keyStart, KeyStart.rotate);
    });

    test('play-score: keys é uma lista de tons, all ou random', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: play-score
title: A
abc: "CDEF|"
keys: []
```

```zywny-exercise
id: b
type: play-score
title: B
abc: "CDEF|"
keys: sempre
```
''');
      final messages = _messages(result);
      expect(messages, hasLength(2));
      expect(messages[0], contains('pelo menos 1 item'));
      expect(messages[1], contains('aceita all, random'));
    });
  });
}

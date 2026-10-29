// EX18 — o `target-notes` na leitura: a grade (texto ou progressão), o alvo, onde
// ele cai, o que se toca entre os alvos (e a fonte), a mão esquerda, a faixa da
// direita e os erros de combinação.
import 'package:test/test.dart';

import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';

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

String _lesson(String body) => '---\nid: um\ntitle: Um\n---\n\n$body';

Future<CourseReadResult> _read(String body) => readCourse(
  MemoryCourseFiles({'course.md': _course, 'lessons/01-um.md': _lesson(body)}),
);

String _messages(CourseReadResult result) =>
    [for (final issue in result.issues) issue.toString()].join('\n');

TargetNotesSpec _only(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as TargetNotesSpec;

void main() {
  group('target-notes: leitura', () {
    test('a terça no tempo 1, com a esquerda e a base (exemplo n4)', () async {
      final result = await _read('''
```zywny-exercise
id: n4-terca-no-um
type: target-notes
title: A 3ª de cada acorde no tempo 1
chart: {progression: ii-V-I, key: C, bars: 8}
target: 3
between: rest
backing: {style: swing, bass: walking}
left: shell-17
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.type, ExerciseType.targetNotes);
      expect(spec.progression, 'ii-V-I');
      expect(spec.progressionBars, 8);
      expect(spec.chartText, isNull);
      expect(spec.key, 'C');
      expect(spec.target, TargetNote.three);
      expect(spec.when, TargetWhen.change, reason: 'o padrão');
      expect(spec.between, TargetBetween.rest);
      expect(spec.left, 'shell-17');
      expect(spec.backing?.style.name, 'swing');
      expect(spec.bpm, 80);
      expect(spec.pass.accuracy, 80);
      expect(spec.pass.source, isNull);
      expect(spec.registerFrom.midi, 60, reason: 'C4, o padrão');
      expect(spec.registerTo.midi, 84, reason: 'C6, o padrão');
    });

    test('guide-tones com a fonte por acorde e o passe (exemplo n5)', () async {
      final result = await _read('''
```zywny-exercise
id: n5-guide-tones
type: target-notes
title: A linha de guide tones
chart: {progression: jazz-blues, key: F}
target: guide-tone
between: free
source: by-chord
bpm: 100
pass: {accuracy: 75, source: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.target, TargetNote.guideTone);
      expect(spec.between, TargetBetween.free);
      expect(spec.source, TargetSource.byChord);
      expect(spec.left, 'none');
      expect(spec.pass.source, 80);
    });

    test('grade de texto, com o alvo e os tempos por padrão', () async {
      final result = await _read('''
```zywny-exercise
id: t-texto
type: target-notes
title: Texto
chart: "| Dm7 | G7 | C |"
key: C
bpm: 60
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.chartText, '| Dm7 | G7 | C |');
      expect(spec.progression, isNull);
      expect(spec.target, TargetNote.three);
      expect(spec.when, TargetWhen.change);
      expect(spec.between, TargetBetween.free);
      expect(spec.source, TargetSource.keyScale);
      expect(spec.backing, isNull);
    });

    test('as escolhas de cada chave (alvo, quando, entre, fonte)', () async {
      final result = await _read('''
```zywny-exercise
id: t-tudo
type: target-notes
title: Tudo
chart: {progression: I-IV-V-I, key: C, bars: 4}
target: 7
when: half-bar
between: enclosure
left: root
register: E4-G5
split: C4
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.target, TargetNote.seven);
      expect(spec.when, TargetWhen.halfBar);
      expect(spec.between, TargetBetween.enclosure);
      expect(spec.left, 'root');
      expect(spec.registerFrom.midi, 64);
      expect(spec.registerTo.midi, 79);
    });

    test('`between: arpeggio-3579` e `target: chord-tone`', () async {
      final result = await _read('''
```zywny-exercise
id: t-arpejo
type: target-notes
title: Arpejo
chart: "| Am7 | D7 |"
key: C
target: chord-tone
between: arpeggio-3579
bpm: 90
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.target, TargetNote.chordTone);
      expect(spec.between, TargetBetween.arpeggio3579);
    });

    test('`source` no `pass` com `between: rest` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: t-erro-passe
type: target-notes
title: Erro
chart: "| C |"
key: C
between: rest
pass: {source: 80}
```
''');
      expect(_messages(result), contains('`source` no `pass`'));
    });

    test('`source` da chave com `between: rest` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: t-erro-fonte
type: target-notes
title: Erro
chart: "| C |"
key: C
between: rest
source: blues
```
''');
      expect(_messages(result), contains('`source` só vale com'));
    });

    test('`half-bar` em 3/4 é erro', () async {
      final result = await _read('''
```zywny-exercise
id: t-meio
type: target-notes
title: Erro
chart: "| C | F |"
key: C
time: 3/4
when: half-bar
```
''');
      expect(_messages(result), contains('`when: half-bar` pede'));
    });

    test('`register` que começa abaixo do `split` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: t-faixa
type: target-notes
title: Erro
chart: "| C |"
key: C
register: C3-C6
split: C4
```
''');
      expect(
        _messages(result),
        contains('`register` começa abaixo do `split`'),
      );
    });

    test('`register` invertida é erro', () async {
      final result = await _read('''
```zywny-exercise
id: t-faixa-invertida
type: target-notes
title: Erro
chart: "| C |"
key: C
register: C6-C4
```
''');
      expect(_messages(result), contains('`register` é uma faixa'));
    });

    test(
      'um alvo, uma esquerda ou um tempo que não existem são erro',
      () async {
        final result = await _read('''
```zywny-exercise
id: t-nomes
type: target-notes
title: Erro
chart: "| C |"
key: C
target: 4
left: voicing-que-nao-existe
between: livre
```
''');
        final text = _messages(result);
        expect(text, contains('target'));
        expect(text, contains('left'));
        expect(text, contains('between'));
      },
    );

    test('o estilo da base tem de ser da fórmula da grade', () async {
      final result = await _read('''
```zywny-exercise
id: t-base
type: target-notes
title: Erro
chart: "| C |"
key: C
time: 3/4
backing: drums
```
''');
      expect(_messages(result), contains('é de 4/4, e a grade é de 3/4'));
    });

    test('`source` no `pass` não vale no `play-chart`', () async {
      final result = await _read('''
```zywny-exercise
id: t-outro-tipo
type: play-chart
title: Erro
chart: "| C |"
key: C
pattern: block
pass: {source: 80}
```
''');
      expect(_messages(result), contains('source'));
    });
  });
}

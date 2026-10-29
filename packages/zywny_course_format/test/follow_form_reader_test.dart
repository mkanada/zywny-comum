// EX20 — o `follow-form` na leitura: o modo, a grade (como no `play-chart`), as
// chaves de cada modo (`questions`, `enter`, `cues` com o `pattern`) e os erros
// de combinação. Os modos que ainda não rodam (`intro-outro`, `break`,
// `trading`) são recusados com "ainda não roda".
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

FollowFormSpec _only(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as FollowFormSpec;

void main() {
  group('follow-form: where', () {
    test('o exemplo n3 (blues por progressão) com os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: n3-onde-estamos
type: follow-form
title: Em que compasso estamos?
mode: where
chart: {progression: blues-12, key: F}
backing: {style: shuffle, bass: walking}
questions: 6
bpm: 100
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.type, ExerciseType.followForm);
      expect(spec.mode, FollowMode.where);
      expect(spec.progression, 'blues-12');
      expect(spec.key, 'F');
      expect(spec.questions, 6);
      expect(spec.answerWindow, 4, reason: 'o padrão');
      expect(spec.choruses, 2, reason: 'o padrão');
      expect(spec.bpm, 100);
      expect(spec.split.midi, 60, reason: 'o padrão C4');
      expect(spec.backing!.style.name, 'shuffle');
      expect(spec.pattern, isNull);
      expect(spec.enter, isNull);
      expect(spec.cues, isEmpty);
    });

    test('`answer-window` e `choruses` valem com `where`', () async {
      final result = await _read('''
```zywny-exercise
id: w
type: follow-form
title: W
mode: where
chart: "| C | Am | F | G |"
key: C
questions: 3
answer-window: 6
choruses: 1
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.answerWindow, 6);
      expect(spec.choruses, 1);
      expect(spec.chartText, '| C | Am | F | G |');
    });

    test('`questions` fora de `where` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: w
type: follow-form
title: W
mode: enter
chart: "| C | Am | F | G |"
key: C
enter: {bars: 3-4, pattern: block}
questions: 3
pass: {accuracy: 70}
```
''');
      expect(
        _messages(result),
        contains('`questions` só vale com `mode: where`'),
      );
    });
  });

  group('follow-form: enter', () {
    test('o exemplo n3 (entrada no compasso 11 e 12)', () async {
      final result = await _read('''
```zywny-exercise
id: n3-turnaround
type: follow-form
title: Entre no turnaround
mode: enter
chart: {progression: blues-12, key: G}
enter: {bars: 11-12, pattern: block}
choruses: 3
backing: {style: shuffle, bass: walking}
bpm: 90
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.mode, FollowMode.enter);
      expect(spec.choruses, 3);
      final enter = spec.enter!;
      expect(enter.bars.toString(), '11-12');
      expect(enter.section, isNull);
      expect(enter.pattern.name, 'block');
    });

    test('`section:` aponta uma seção da grade', () async {
      final result = await _read('''
```zywny-exercise
id: e
type: follow-form
title: Entre na ponte
mode: enter
chart: |
  A: | C | F | C | G |
  B: | Am | F | G | G |
enter: {section: B, pattern: block}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      expect(_only(result).enter!.section, 'B');
    });

    test('`bars` além do fim da grade é erro', () async {
      final result = await _read('''
```zywny-exercise
id: e
type: follow-form
title: E
mode: enter
chart: "| C | Am | F | G |"
key: C
enter: {bars: 3-6, pattern: block}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('a grade tem 4'));
    });

    test('`section` que a grade não tem é erro', () async {
      final result = await _read('''
```zywny-exercise
id: e
type: follow-form
title: E
mode: enter
chart: "| C | Am | F | G |"
key: C
enter: {section: B, pattern: block}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('não há a seção `B`'));
    });

    test('`enter` sem `bars` nem `section` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: e
type: follow-form
title: E
mode: enter
chart: "| C | Am | F | G |"
key: C
enter: {pattern: block}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('um dos dois'));
    });

    test(
      '`enter` de outro modo é erro, e o modo enter sem ele também',
      () async {
        final result = await _read('''
```zywny-exercise
id: e
type: follow-form
title: E
mode: enter
chart: "| C | Am | F | G |"
key: C
pass: {accuracy: 70}
```
''');
        expect(_messages(result), contains('`mode: enter` pede `enter`'));
      },
    );
  });

  group('follow-form: cues', () {
    test('o exemplo n4 (sinais com seções), com o molde', () async {
      final result = await _read('''
```zywny-exercise
id: n4-gospel-sinais
type: follow-form
title: Siga o regente
mode: cues
chart: |
  A: | C | F | C | G |
  B: | Am | F | G | G |
  C: | F | G | C | C |
cues: [again, next, back-to-A, end]
pattern: straight-beat
bpm: 84
pass: {accuracy: 75}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.mode, FollowMode.cues);
      expect(spec.cues, [
        FormSignal.again,
        FormSignal.next,
        FormSignal.backToA,
        FormSignal.end,
      ]);
      expect(spec.pattern!.name, 'straight-beat');
    });

    test('sem `cues`, são `again`, `next` e `end`', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: |
  A: | C | F | C | G |
  B: | Am | F | G | G |
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      expect(_only(result).cues, [
        FormSignal.again,
        FormSignal.next,
        FormSignal.end,
      ]);
    });

    test('um sinal só, sem lista', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
cues: end
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      expect(_only(result).cues, [FormSignal.end]);
    });

    test('sem `pattern` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('`mode: cues` pede `pattern`'));
    });

    test('um sinal que não existe, com a sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
cues: [agan, end]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('você quis dizer `again`'));
    });

    test('sem `end` nem `tag`, a forma não acaba', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
cues: [again]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('precisa de `end` ou `tag`'));
    });

    test('`bridge` sem a seção `B:` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: |
  A: | C | F | C | G |
  B: | Am | F | G | G |
cues: [bridge, end]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty, reason: 'a grade tem a seção B');
      final bad = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
cues: [bridge, end]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(bad), contains('`bridge` vai para a seção `B:`'));
    });

    test('`next` numa grade de uma seção só é erro', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
cues: [next, end]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(
        _messages(result),
        contains('pede uma grade com mais de uma seção'),
      );
    });

    test('`tag` com menos de quatro compassos é erro', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | F | G |"
key: C
cues: [tag]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('`tag` volta quatro compassos'));
    });

    test('`choruses` com `cues` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: c
type: follow-form
title: C
mode: cues
chart: "| C | Am | F | G |"
key: C
choruses: 2
cues: [end]
pattern: block
pass: {accuracy: 70}
```
''');
      expect(
        _messages(result),
        contains('`choruses` não vale com `mode: cues`'),
      );
    });
  });

  group('follow-form: modos ainda não rodam', () {
    for (final mode in ['intro-outro', 'break', 'trading']) {
      test('`mode: $mode` é recusado', () async {
        final result = await _read('''
```zywny-exercise
id: x
type: follow-form
title: X
mode: $mode
chart: "| C | Am | F | G |"
key: C
pass: {accuracy: 70}
```
''');
        expect(_messages(result), contains('ainda não roda'));
        expect(result.course, isNull, reason: 'o erro impede o curso');
      });
    }

    test('um modo que não existe, com a sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: follow-form
title: X
mode: wheres
chart: "| C | Am | F | G |"
key: C
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('você quis dizer `where`'));
    });
  });
}

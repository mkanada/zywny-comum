// EX13 — o `listen-groove` na leitura: os grooves (com os nomes do vocabulário),
// o `count` e os erros da lista.
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

ListenGrooveSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as ListenGrooveSpec;

void main() {
  group('listen-groove: leitura', () {
    test('lê os grooves na ordem do autor, com count e pass', () async {
      final result = await _read('''
```zywny-exercise
id: n3-reto-ou-swing
type: listen-groove
title: Reto ou swingado?
grooves: [straight-eighths, swing-eighths]
count: 8
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.type, ExerciseType.listenGroove);
      expect(spec.grooves, [
        ListenGroove.straightEighths,
        ListenGroove.swingEighths,
      ]);
      expect(spec.count, 8);
      expect(spec.pass.accuracy, 80);
    });

    test('count vale 8 quando o autor não diz', () async {
      final result = await _read('''
```zywny-exercise
id: n3-clave
type: listen-groove
title: Clave
grooves: [clave-3-2, clave-2-3]
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      expect(_spec(result).count, 8);
    });

    test('os nove grooves do vocabulário se leem pelos nomes de fio', () async {
      final result = await _read('''
```zywny-exercise
id: n5-todos
type: listen-groove
title: Todos
grooves: [straight-eighths, swing-eighths, shuffle-12-8, clave-3-2, clave-2-3, bossa, samba, waltz, six-eight]
count: 40
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.grooves, ListenGroove.values);
      expect(spec.count, 40);
      expect(
        [for (final groove in ListenGroove.values) groove.wire],
        [
          'straight-eighths',
          'swing-eighths',
          'shuffle-12-8',
          'clave-3-2',
          'clave-2-3',
          'bossa',
          'samba',
          'waltz',
          'six-eight',
        ],
      );
    });

    test('time-limit vale como nos outros exercícios de pergunta', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [bossa, samba]
pass: {accuracy: 80, time-limit: 10}
```
''');
      expect(_messages(result), isEmpty);
    });
  });

  group('listen-groove: erros', () {
    test('menos de dois grooves', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [bossa]
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`grooves` precisa de pelo menos 2 itens.'),
      );
    });

    test('falta grooves', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
count: 5
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          'falta a chave obrigatória `grooves` no exercício `listen-groove`.',
        ),
      );
    });

    test('nome de groove desconhecido, com sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [swing-eighth, bossa]
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('groove `swing-eighth` desconhecido'));
      expect(_messages(result), contains('você quis dizer `swing-eighths`?'));
    });

    test('nome de groove sem sugestão, com a lista dos nomes', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [valsa-lenta, bossa]
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('groove `valsa-lenta` desconhecido (use straight-eighths, '),
      );
    });

    test('groove repetido', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [bossa, samba, bossa]
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`grooves` repete um groove.'));
    });

    test('count fora de 1 a 40', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [bossa, samba]
count: 41
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`count` precisa estar entre 1 e 40 (recebi 41).'),
      );
    });

    test('speed não vale no listen-groove (só com tempo real)', () async {
      final result = await _read('''
```zywny-exercise
id: n3-x
type: listen-groove
title: X
grooves: [bossa, samba]
pass: {accuracy: 80, speed: 90}
```
''');
      expect(
        _messages(result),
        contains('`speed` não vale em `listen-groove`'),
      );
    });
  });
}

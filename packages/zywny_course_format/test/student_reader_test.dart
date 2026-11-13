// T18 (LP18) — a leitura de `transpose` e `student` no `play-score`, e do
// `.mxl` (o MusicXML compactado) no `file`, com os erros de combinação.
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

const _musicXml = '<score-partwise version="3.1"/>';

String _lesson(String body) => '---\nid: um\ntitle: Um\n---\n\n$body';

Future<CourseReadResult> _read(String body) => readCourse(
  MemoryCourseFiles({
    'course.md': _course,
    'lessons/01-um.md': _lesson(body),
    'media/peca.musicxml': _musicXml,
    'media/ode.mxl': _musicXml,
  }),
);

List<String> _messages(CourseReadResult result) => [
  for (final issue in result.issues) issue.toString(),
];

/// Um `play-score` de arquivo, com [extra] (as chaves depois de `file:`).
String _playScore(String extra, {String file = 'media/peca.musicxml'}) =>
    '''
```zywny-exercise
id: n2-peca
type: play-score
title: Toque a peça
file: $file
mode: realtime
$extra
```
''';

PlayScoreSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as PlayScoreSpec;

void main() {
  _parte6();
}

void _parte1() {
  test('sem as chaves: transpose 0 e student vazio', () async {
    final result = await _read(_playScore('pass: {accuracy: 100}'));
    expect(_messages(result), isEmpty);
    final spec = _spec(result);
    expect(spec.transpose, 0);
    expect(spec.student, isEmpty);
  });
  test('transpose e student lidos com file', () async {
    final result = await _read(
      _playScore(
        'transpose: -2\n'
        'student: ["a b c", "d e"]\n'
        'pass: {accuracy: 100}',
      ),
    );
    expect(_messages(result), isEmpty);
    final spec = _spec(result);
    expect(spec.transpose, -2);
    expect(spec.student, [
      ['a', 'b', 'c'],
      ['d', 'e'],
    ]);
  });
  test('transpose fora da faixa (13) é erro', () async {
    final result = await _read(
      _playScore('transpose: 13\npass: {accuracy: 100}'),
    );
    expect(_messages(result).join('\n'), contains('transpose'));
  });
  test('transpose com keys é erro', () async {
    final result = await _read(
      _playScore('transpose: 2\nkeys: [G]\npass: {accuracy: 100}'),
    );
    expect(
      _messages(result).join('\n'),
      contains('`transpose` não vale junto com `keys` nem `cycle`'),
    );
  });
}

void _parte2() {
  test('transpose com cycle é erro', () async {
    final result = await _read(
      _playScore('transpose: 2\ncycle: 5ths\npass: {accuracy: 100}'),
    );
    expect(
      _messages(result).join('\n'),
      contains('`transpose` não vale junto com `keys` nem `cycle`'),
    );
  });
  test('student com abc é erro', () async {
    final result = await _read('''
```zywny-exercise
id: n2-peca
type: play-score
title: Toque a peça
abc: |
  X:1
  K:C
  CDEF|
mode: realtime
student: ["a b"]
pass: {accuracy: 100}
```
''');
    expect(
      _messages(result).join('\n'),
      contains('`student` só vale com `file`'),
    );
  });
  test('um id repetido em student é erro', () async {
    final result = await _read(
      _playScore('student: ["a b", "b c"]\npass: {accuracy: 100}'),
    );
    expect(
      _messages(result).join('\n'),
      contains('o id `b` aparece duas vezes em `student`'),
    );
  });
}

void _parte3() {
  test('um trecho vazio em student é erro', () async {
    // O `stringList` genérico recusa o item vazio ("esperava um texto."): o
    // erro existe e cai na linha do exercício, sem mensagem própria.
    final result = await _read(
      _playScore('student: ["a b", ""]\npass: {accuracy: 100}'),
    );
    expect(_messages(result).join('\n'), contains('esperava um texto'));
  });
  test('student com practice cumulative é erro', () async {
    final result = await _read(
      _playScore(
        'student: ["a b"]\npractice: cumulative\npass: {accuracy: 100}',
      ),
    );
    expect(
      _messages(result).join('\n'),
      contains('`student` não vale com `practice: cumulative`'),
    );
  });
  test('student com hand sequence é erro', () async {
    final result = await _read(
      _playScore('student: ["a b"]\nhand: sequence\npass: {accuracy: 100}'),
    );
    expect(
      _messages(result).join('\n'),
      contains(
        '`student` não vale com `practice: cumulative` nem `hand: sequence`',
      ),
    );
  });
}

void _parte4() {
  test('file .mxl sozinho lê, com o caminho original', () async {
    final result = await _read(
      _playScore('pass: {accuracy: 100}', file: 'media/ode.mxl'),
    );
    expect(_messages(result), isEmpty);
    expect((_spec(result).source as FileSource).path, 'media/ode.mxl');
  });
  test('file .mxl com keys é erro', () async {
    final result = await _read(
      _playScore('keys: [G]\npass: {accuracy: 100}', file: 'media/ode.mxl'),
    );
    expect(
      _messages(result).join('\n'),
      contains(
        'um `.mxl` não vale com `keys`, `cycle` nem `practice: cumulative`',
      ),
    );
  });
  test('file .mxl com cycle é erro', () async {
    final result = await _read(
      _playScore('cycle: 4ths\npass: {accuracy: 100}', file: 'media/ode.mxl'),
    );
    expect(
      _messages(result).join('\n'),
      contains(
        'um `.mxl` não vale com `keys`, `cycle` nem `practice: cumulative`',
      ),
    );
  });
}

void _parte5() {
  test('file .mxl com practice cumulative é erro', () async {
    final result = await _read(
      _playScore(
        'practice: cumulative\npass: {accuracy: 100}',
        file: 'media/ode.mxl',
      ),
    );
    expect(
      _messages(result).join('\n'),
      contains(
        'um `.mxl` não vale com `keys`, `cycle` nem `practice: cumulative`',
      ),
    );
  });
  test('zywny-score continua recusando o .mxl', () async {
    final result = await _read('''
```zywny-score
file: media/ode.mxl
```
''');
    expect(_messages(result), isNotEmpty);
    expect(_messages(result).join('\n'), contains('.musicxml'));
  });
}

// Testes: transpose e student: leitura · .mxl no play-score
void _parte6() {
  group('transpose e student: leitura', () {
    _parte1();
    _parte2();
    _parte3();
  });
  group('.mxl no play-score', () {
    _parte4();
    _parte5();
  });
}

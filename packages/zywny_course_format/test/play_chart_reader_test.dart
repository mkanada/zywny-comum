// EX11 — o `play-chart` na leitura: a grade (texto ou progressão), o molde
// (nome ou mapa), o swing, os medidores e os erros da especificação.
import 'package:test/test.dart';

import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_music/comping_patterns.dart';

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

void main() {
  group('play-chart: leitura', () {
    test('grade de texto com um padrão da biblioteca', () async {
      final result = await _read('''
```zywny-exercise
id: n2-oom-pah-c
type: play-chart
title: Oom-pah em Dó
chart: "|: C | Am | F | G :|"
key: C
pattern: oom-pah
bpm: 80
pass: {accuracy: 85}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayChartSpec;
      expect(spec.type, ExerciseType.playChart);
      expect(spec.chartText, '|: C | Am | F | G :|');
      expect(spec.progression, isNull);
      expect(spec.key, 'C');
      expect(spec.time, '4/4');
      expect(spec.pattern.name, 'oom-pah');
      expect(spec.pattern.grid, 4);
      expect(spec.bpm, 80);
      expect(spec.choruses, 1);
      expect(spec.swing, isNull);
      expect(spec.strict, isTrue, reason: 'D-EXE-ACORDE: strict por padrão');
      expect(spec.strictRhythm, isFalse);
      expect(spec.metronome, isTrue);
      expect(spec.show, ChartShow.chords);
    });

    test(
      'progressão da biblioteca, molde escrito, swing e medidores',
      () async {
        final result = await _read('''
```zywny-exercise
id: n3-blues-boogie
type: play-chart
title: Blues em Sol com boogie na esquerda
chart: {progression: blues-12, key: G}
pattern: {grid: 8, left: "1 5 6 5 1 5 6 5", right: ". . C . . . C ."}
swing: 67
bpm: 90
choruses: 2
keys: [G, C, F]
pass: {accuracy: 80, steadiness: 50, choruses: 2}
```
''');
        expect(_messages(result), isEmpty);
        final spec =
            result.course!.lessons.single.exercises.single as PlayChartSpec;
        expect(spec.progression, 'blues-12');
        expect(spec.chartText, isNull);
        expect(spec.key, 'G');
        expect(spec.pattern.name, 'molde');
        expect(
          spec.pattern.time,
          isNull,
          reason: 'o molde escrito vale em todo',
        );
        expect(spec.pattern.leftBars.single.first.degrees, ['1']);
        expect(spec.swing, 67);
        expect(spec.choruses, 2);
        expect(spec.keys, isA<FixedKeys>());
        expect(spec.pass.steadiness, 50);
      },
    );

    test('o molde de dois compassos e a progressão com bars', () async {
      final result = await _read('''
```zywny-exercise
id: n4-montuno
type: play-chart
title: Montuno
chart: {progression: ii-V-I, key: C, bars: 4}
pattern: montuno
time: 4/4
bpm: 100
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayChartSpec;
      expect(spec.progressionBars, 4);
      expect(spec.pattern.bars, 2);
    });

    test('o padrão de valsa numa grade de 3/4 é aceito', () async {
      final result = await _read('''
```zywny-exercise
id: n2-valsa
type: play-chart
title: Valsa
chart: "| C | F | G | C |"
time: 3/4
pattern: oom-pah-pah
bpm: 120
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
    });
  });

  group('play-chart: erros', () {
    test('padrão que não existe, com sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | F |"
pattern: oom-pa
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('não há o padrão `oom-pa`'));
      expect(_messages(result), contains('você quis dizer `oom-pah`'));
    });

    test('molde de 3/4 numa grade de 4/4', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | F |"
pattern: oom-pah-pah
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('o molde `oom-pah-pah` é de 3/4, e a grade é de 4/4'),
      );
    });

    test('linha do molde com número de símbolos diferente de grid', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | F |"
pattern: {grid: 8, left: "1 5 6 5 1", right: ". . C . . . C ."}
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('um compasso do molde tem 5 símbolos, e `grid` pede 8'),
      );
    });

    test('swing sem colcheias no molde', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | F |"
pattern: walking-two
swing: 67
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`swing` pede colcheias no molde'));
    });

    test('progressão que não está na biblioteca', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: {progression: nope, key: C}
pattern: block
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('não há a progressão `nope`'));
    });

    test('`key` fora do mapa quando a grade vem da biblioteca', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: {progression: I-IV-V-I}
key: C
pattern: block
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          '`key` fica dentro de `chart` quando a grade vem da biblioteca',
        ),
      );
    });

    test('a grade de texto com acorde que não existe', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | Hm |"
pattern: block
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('na grade (coluna'));
    });

    test(
      'a mão esquerda e a direita com número de compassos diferente',
      () async {
        final result = await _read('''
```zywny-exercise
id: n4-x
type: play-chart
title: X
chart: "| C | F |"
pattern: {grid: 4, left: "1 . . . | 5 . . .", right: ". C . C"}
bpm: 80
pass: {accuracy: 80}
```
''');
        expect(_messages(result), contains('as duas mãos têm de ter o mesmo'));
      },
    );

    test('o andamento do modo espera não vale no play-chart', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: play-chart
title: X
chart: "| C | F |"
pattern: block
bpm: 80
pass: {accuracy: 80, speed: 90}
```
''');
      expect(_messages(result), contains('`speed` não vale em `play-chart`'));
    });
  });

  test('o nome do padrão da biblioteca é o que o validador conhece', () {
    for (final name in compingPatternNames) {
      expect(compingPatternNamed(name), isNotNull, reason: name);
    }
  });
}

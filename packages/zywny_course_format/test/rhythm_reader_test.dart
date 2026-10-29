// EX13 — o `rhythm` com duas mãos e com `groove` na leitura: os moldes
// (`right` e `left`), o `hands`, o `split` e os erros que cruzam as chaves.
import 'package:test/test.dart';

import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_music/rhythm_grooves.dart';

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

/// O molde de [bars] como se escreve (`X . | A .`).
String _text(List<List<RhythmSymbol>> bars) => [
  for (final bar in bars)
    bar
        .map(
          (symbol) => switch (symbol) {
            RhythmSymbol.rest => '.',
            RhythmSymbol.attack => 'X',
            RhythmSymbol.accent => 'A',
          },
        )
        .join(' '),
].join(' | ');

/// A linha (base 1) da primeira linha de [body] que começa com [prefix].
int _lineStarting(String body, String prefix) =>
    _lesson(body).split('\n').indexWhere((line) => line.startsWith(prefix)) + 1;

RhythmSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as RhythmSpec;

void main() {
  group('rhythm com groove e moldes: leitura', () {
    test('groove lê o groove certo e copia os moldes dele', () async {
      final result = await _read('''
```zywny-exercise
id: n4-clave
type: rhythm
title: Clave 3-2 na direita, tumbao na esquerda
groove: clave-son-3-2
bpm: 90
measures: 4
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.groove!.name, 'clave-son-3-2');
      expect(spec.hands, 2, reason: 'o groove de duas mãos põe as duas');
      expect(spec.time, '4/4');
      expect(spec.bpm, 90);
      expect(spec.measures, 4);
      expect(spec.figures, isNull);
      expect(spec.abc, isNull);
      expect(spec.split.toString(), 'C4');
      expect(_text(spec.right!), 'X . . X . . X . | . . X . X . . .');
      expect(_text(spec.left!), '. . . X . . X . | . . . X . . X .');
    });

    test(
      'right e left escritos, sem hands: as duas mãos saem do left',
      () async {
        final result = await _read('''
```zywny-exercise
id: n2-dois-por-quatro
type: rhythm
title: Dois contra quatro
right: "X . X . | X X X X"
left: "X . . . | . . X ."
pass: {accuracy: 80}
```
''');
        expect(_messages(result), isEmpty);
        final spec = _spec(result);
        expect(spec.groove, isNull);
        expect(spec.hands, 2);
        expect(spec.time, '4/4');
        expect(spec.measures, 4, reason: 'o padrão de `measures` nos moldes');
        expect(_text(spec.right!), 'X . X . | X X X X');
        expect(_text(spec.left!), 'X . . . | . . X .');
        expect(spec.figures, isNull);
        expect(spec.abc, isNull);
      },
    );

    test('um right só é uma mão escrita, e `measures` fica no molde', () async {
      final result = await _read('''
```zywny-exercise
id: n1-so-direita
type: rhythm
title: Só a direita
right: "X . X . X . X ."
measures: 8
pass: {accuracy: 85}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.hands, 1);
      expect(spec.left, isNull);
      expect(_text(spec.right!), 'X . X . X . X .');
      expect(spec.measures, 8);
    });

    test('o compasso de 3/4 vai para o molde', () async {
      final result = await _read('''
```zywny-exercise
id: n1-valsa
type: rhythm
title: Valsa
time: 3/4
right: "X . . | X . ."
pass: {accuracy: 85}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.time, '3/4');
      expect(_text(spec.right!), 'X . . | X . .');
    });

    test(
      'o split de um groove de duas mãos é lido, e hands: two confere',
      () async {
        final result = await _read('''
```zywny-exercise
id: n3-tres-contra-dois
type: rhythm
title: Dois contra três
groove: two-against-three
hands: two
split: C2
pass: {accuracy: 85}
```
''');
        expect(_messages(result), isEmpty);
        final spec = _spec(result);
        expect(spec.hands, 2);
        expect(spec.split.toString(), 'C2');
        expect(spec.groove!.name, 'two-against-three');
      },
    );

    test('ganza: um groove de uma mão, com os acentos no molde', () async {
      final result = await _read('''
```zywny-exercise
id: n4-ganza
type: rhythm
title: O ganzá
groove: ganza
bpm: 80
measures: 4
pass: {accuracy: 85, accents: 12}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.hands, 1);
      expect(spec.left, isNull);
      expect(
        spec.right!.single.where((s) => s == RhythmSymbol.accent),
        hasLength(4),
      );
    });

    test('o sorteio e o ABC continuam com uma mão e sem moldes', () async {
      final result = await _read('''
```zywny-exercise
id: n1-sorteio
type: rhythm
title: Sorteio
figures: [quarter, eighth, quarter-rest]
pass: {speed: 80}
```

```zywny-exercise
id: n1-abc
type: rhythm
title: ABC
abc: "C"
pass: {accuracy: 85}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      final sorteio = specs[0] as RhythmSpec;
      expect(sorteio.hands, 1);
      expect(sorteio.split.toString(), 'C4');
      expect(sorteio.groove, isNull);
      expect(sorteio.right, isNull);
      expect(sorteio.left, isNull);
      final abc = specs[1] as RhythmSpec;
      expect(abc.hands, 1);
      expect(abc.right, isNull);
    });
  });

  group('rhythm com groove e moldes: erros', () {
    test('hands: two sem left nem groove de duas mãos', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
hands: two
figures: [quarter, eighth, quarter-rest]
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`hands: two` pede `left:` ou um `groove` de duas mãos.'),
      );
    });

    test('groove de duas mãos com hands: one', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: clave-son-3-2
hands: one
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('o groove `clave-son-3-2` toca as duas mãos: tire `hands:`.'),
      );
    });

    test('ganza, de uma mão, com hands: two', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: ganza
hands: two
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('o groove `ganza` toca só a mão direita: tire `hands: two`.'),
      );
    });

    test('groove com figures é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: bossa-clave
figures: [quarter, eighth, quarter-rest]
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          '`figures` não vale com `groove` ou `right`: o ritmo é o molde.',
        ),
      );
    });

    test('right com abc é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
right: "X . X ."
abc: "C"
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`abc` não vale com `groove` ou `right`: o ritmo é o molde.'),
      );
    });

    test('groove com right ou left é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: charleston
right: "X . X ."
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          '`groove` não vale com `right` e `left`: o groove já traz os moldes.',
        ),
      );
    });

    test('left sem right é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
left: "X . . ."
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`left` pede `right`: os dois moldes vêm juntos.'),
      );
    });

    test('left com hands: one é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
hands: one
right: "X . X ."
left: "X . . ."
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`left:` não vale com `hands: one`.'));
    });

    test('molde com um token errado, na linha do molde', () async {
      const body = '''
```zywny-exercise
id: n1-x
type: rhythm
title: X
right: "X . Q ."
pass: {accuracy: 80}
```
''';
      final result = await _read(body);
      expect(
        _messages(result),
        contains(
          '`right`: `Q` não é um símbolo do ritmo (use `X`, `A` ou `.`).',
        ),
      );
      final issue = result.issues.singleWhere(
        (issue) => issue.message.contains('não é um símbolo do ritmo'),
      );
      expect(issue.line, _lineStarting(body, 'right:'));
    });

    test('moldes de números de compassos diferentes', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: rhythm
title: X
right: "X . X . | X X X X"
left: "X . . ."
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          '`left` tem 1 compasso(s) e `right` tem 2: as duas mãos têm de ter o '
          'mesmo número de compassos.',
        ),
      );
    });

    test('measures que não é múltiplo do molde', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: rhythm
title: X
right: "X . X . | X X X X"
measures: 3
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          '`measures` precisa ser múltiplo de 2, o número de compassos do molde '
          '(recebi 3).',
        ),
      );
    });

    test('molde de 3 compassos com o measures padrão (4)', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: rhythm
title: X
right: "X . X . | X X X X | X . . ."
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          'o molde tem 3 compasso(s), e `measures` (padrão 4) não é múltiplo '
          'disso: escreva `measures:`.',
        ),
      );
    });

    test('measures múltiplo do molde passa', () async {
      final result = await _read('''
```zywny-exercise
id: n2-x
type: rhythm
title: X
right: "X . X . | X X X X"
measures: 8
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      expect(_spec(result).measures, 8);
    });

    test('o time do exercício que não é o do groove', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: clave-son-3-2
time: 3/4
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('o groove `clave-son-3-2` é de 4/4, e o exercício é de 3/4.'),
      );
    });

    test('split sem duas mãos é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
right: "X . X ."
split: C2
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`split` só vale com duas mãos'));
    });

    test('note com groove ou molde é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: ganza
note: C5
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('`note` só vale no sorteio, com `figures`.'),
      );
    });

    test('sem figures, abc, groove nem right, o autor é avisado', () async {
      final result = await _read('''
```zywny-exercise
id: n1-x
type: rhythm
title: X
bpm: 80
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains(
          'informe `figures` (ritmo sorteado), `abc` (ritmo escrito), `groove` '
          'ou `right` (molde).',
        ),
      );
    });

    test('groove com nome errado sugere o certo', () async {
      final result = await _read('''
```zywny-exercise
id: n4-x
type: rhythm
title: X
groove: two-against-thre
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`groove` aceita two-against-three'));
      expect(
        _messages(result),
        contains('você quis dizer `two-against-three`'),
      );
    });
  });
}

// EX12 — o `backing:` do `play-chart` na leitura: o texto `drums`, o mapa (estilo,
// baixo, volume, intro), o estilo que combina com o molde e os erros.
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

PlayChartSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as PlayChartSpec;

void main() {
  group('play-chart: backing', () {
    test('backing: drums é a bateria do estilo do molde, sem baixo', () async {
      final result = await _read('''
```zywny-exercise
id: n2-oom-pah-base
type: play-chart
title: Oom-pah com a bateria
chart: "| C | F | G | C |"
key: C
pattern: oom-pah
backing: drums
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final backing = _spec(result).backing!;
      expect(backing.style.name, 'straight');
      expect(backing.drums, isTrue);
      expect(backing.bass, BackingBass.none);
      expect(backing.volume, 70);
      expect(backing.intro, 1);
      expect(
        _spec(result).metronome,
        isFalse,
        reason: 'com a base, o metrônomo começa desligado',
      );
    });

    test('o mapa escolhe o estilo, o baixo, o volume e a intro', () async {
      final result = await _read('''
```zywny-exercise
id: n3-blues-base
type: play-chart
title: Blues com a banda
chart: {progression: blues-12, key: G}
pattern: boogie
backing: {style: shuffle, bass: walking, volume: 55, intro: 2}
bpm: 96
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final backing = _spec(result).backing!;
      expect(backing.style.name, 'shuffle');
      expect(backing.bass, BackingBass.walking);
      expect(backing.volume, 55);
      expect(backing.intro, 2);
    });

    test('sem style, o mapa usa o do molde; o baixo padrão é a 5ª', () async {
      final result = await _read('''
```zywny-exercise
id: n3-boogie-base
type: play-chart
title: Boogie com base
chart: "| C | F | G | C |"
key: C
pattern: boogie
backing: {drums: true}
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final backing = _spec(result).backing!;
      expect(backing.style.name, 'shuffle');
      expect(backing.bass, BackingBass.rootFifth);
    });

    test('o metrônomo pedido continua ligado com a base', () async {
      final result = await _read('''
```zywny-exercise
id: n2-com-clique
type: play-chart
title: Com clique
chart: "| C | F |"
key: C
pattern: block
backing: drums
metronome: true
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      expect(_spec(result).metronome, isTrue);
    });

    test('um estilo que não existe sugere o parecido', () async {
      final result = await _read('''
```zywny-exercise
id: n2-erro
type: play-chart
title: Erro
chart: "| C | F |"
key: C
pattern: block
backing: {style: shufle}
pass: {accuracy: 80}
```
''');
      expect(
        _messages(result),
        contains('não há o estilo `shufle`'),
      );
      expect(_messages(result), contains('você quis dizer `shuffle`'));
    });

    test('o estilo de outro compasso que a grade é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n2-valsa
type: play-chart
title: Valsa
chart: "| C | F |"
key: C
pattern: block
backing: {style: waltz}
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('o estilo `waltz` é de 3/4'));
    });

    test('walking em 3/4 é aviso, e a leitura segue', () async {
      final result = await _read('''
```zywny-exercise
id: n2-walk-3-4
type: play-chart
title: Walking em 3/4
chart: {progression: I-IV-V-I, key: C, bars: 4}
time: 3/4
pattern: oom-pah-pah
backing: {style: waltz, bass: walking}
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('walking em 3/4 soa estranho'));
      expect(_messages(result), contains('use `root`'));
    });

    test('o tipo errado de `backing:` é recusado', () async {
      final result = await _read('''
```zywny-exercise
id: n2-tipo
type: play-chart
title: Tipo
chart: "| C | F |"
key: C
pattern: block
backing: 42
pass: {accuracy: 80}
```
''');
      expect(_messages(result), contains('`backing` precisa ser `drums`'));
    });
  });
}

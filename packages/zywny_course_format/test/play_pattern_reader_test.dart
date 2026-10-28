// EX06 — o `play-pattern` na leitura: os padrões e as chaves, o tom (`key:`,
// `keys:`, `cycle:`), o `motif`, as chaves que só valem com um padrão e o aviso
// do dedilhado sem tabela.
import 'package:test/test.dart';
import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_music/scale.dart';

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

List<String> _messages(CourseReadResult result) => [
  for (final issue in result.issues) issue.toString(),
];

void main() {
  group('play-pattern: leitura', () {
    test('escala de dó em duas oitavas, com os padrões do formato', () async {
      final result = await _read('''
```zywny-exercise
id: n2-escala
type: play-pattern
title: Escala maior, duas oitavas
pattern: scale
keys: [C, G, D, A, E]
octaves: 2
hand: right
mode: realtime
bpm: 72
grouping: 4
articulation: legato
pass: {accuracy: 90, rounds: 5}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayPatternSpec;
      expect(spec.type, ExerciseType.playPattern);
      expect(spec.pattern, PatternKind.scale);
      expect(spec.scale, ScaleKind.major);
      expect(spec.keys, isA<FixedKeys>());
      expect((spec.keys as FixedKeys).keys, ['C', 'G', 'D', 'A', 'E']);
      expect(spec.octaves, 2);
      expect(spec.hand, PatternHand.right);
      expect(spec.mode, PlayMode.realtime);
      expect(spec.bpm, 72);
      // `grouping: 4` é número no YAML e vale como a palavra '4'.
      expect(spec.grouping, PatternGrouping.four);
      expect(spec.articulation, PatternArticulation.legato);
      expect(spec.pass.rounds, 5);
    });

    test('padrões de três notas e sequência, com os valores padrão', () async {
      final result = await _read('''
```zywny-exercise
id: n4-tres-notas
type: play-pattern
title: Padrão de 3 notas
pattern: three-note
order: 132
source: scale
keys: all
```

```zywny-exercise
id: n5-sequencia
type: play-pattern
title: Sequência
pattern: sequence
motif: [1, 2, 3, 1]
key: F
```
''');
      expect(_messages(result), isEmpty);
      final exercises = result.course!.lessons.single.exercises.toList();
      final three = exercises[0] as PlayPatternSpec;
      expect(three.order, PatternOrder.order132);
      expect(three.source, PatternSource.scale);
      expect(three.keys, isA<AllKeys>());
      final sequence = exercises[1] as PlayPatternSpec;
      expect(sequence.motif, [1, 2, 3, 1]);
      expect(sequence.key, 'F');
      // Sem as chaves, o padrão é o da tabela do EX06.
      expect(sequence.hand, PatternHand.right);
      expect(sequence.direction, PatternDirection.upDown);
      expect(sequence.fingering, isTrue);
      expect(sequence.grouping, PatternGrouping.two);
      expect(sequence.mode, PlayMode.wait);
    });

    test('ciclo e início pelo dia, como no play-score', () async {
      final result = await _read('''
```zywny-exercise
id: n5-ciclo
type: play-pattern
title: Arpejo pelo ciclo
pattern: arpeggio
chord: m
cycle: 5ths
key-start: rotate
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayPatternSpec;
      expect(spec.chord, 'm');
      expect(spec.cycle, KeyCycle.fifths);
      expect(spec.keyStart, KeyStart.rotate);
    });

    test('dedilhado em escala de tom com tabela: sem aviso', () async {
      final result = await _read('''
```zywny-exercise
id: n2-dedilhado
type: play-pattern
title: Dedilhado
pattern: scale
key: G
fingering: true
```
''');
      expect(_messages(result), isEmpty);
    });
  });

  group('play-pattern: erros e avisos', () {
    test('sequência sem motivo é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n5-sem-motivo
type: play-pattern
title: Sem motivo
pattern: sequence
```
''');
      expect(
        _messages(result).join('\n'),
        contains('`pattern: sequence` pede `motif`'),
      );
    });

    test('grau de motivo fora de 1 a 7 é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n5-grau
type: play-pattern
title: Grau
pattern: sequence
motif: [1, 9]
```
''');
      expect(_messages(result).join('\n'), contains('graus de 1 a 7'));
    });

    test('`figure` com um padrão que não o usa é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n2-figura
type: play-pattern
title: Figura
pattern: scale
figure: alberti
```
''');
      expect(
        _messages(result).join('\n'),
        contains('`figure` só vale com `pattern: broken-chord`'),
      );
    });

    test('`key` com `keys` é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n2-dois-tons
type: play-pattern
title: Dois tons
pattern: scale
key: C
keys: [G, D]
```
''');
      expect(
        _messages(result).join('\n'),
        contains('`key` não vale com `keys`'),
      );
    });

    test('`key` com `cycle` é o ponto de partida do ciclo, e vale', () async {
      final result = await _read('''
```zywny-exercise
id: n2-ciclo-em-sol
type: play-pattern
title: Ciclo a partir de sol
pattern: scale
key: G
cycle: 5ths
```
''');
      expect(_messages(result), isEmpty);
    });

    test('`keys` e `cycle` juntos continuam sendo erro (EX05)', () async {
      final result = await _read('''
```zywny-exercise
id: n2-keys-cycle
type: play-pattern
title: Os dois
pattern: scale
keys: [G]
cycle: 4ths
```
''');
      expect(_messages(result), isNotEmpty);
    });

    test('dedilhado pedido num padrão sem tabela só avisa', () async {
      final result = await _read('''
```zywny-exercise
id: n4-sem-tabela
type: play-pattern
title: Sem tabela
pattern: three-note
fingering: true
```
''');
      final issues = result.issues.toList();
      expect(issues, hasLength(1));
      expect(issues.single.severity, IssueSeverity.warning);
      expect(issues.single.message, contains('sem dedilhado'));
    });

    test(
      'arpejo de sétima pedindo dedilhado só avisa (o livro não traz)',
      () async {
        final result = await _read('''
```zywny-exercise
id: n4-arpejo-sete
type: play-pattern
title: Arpejo de sétima
pattern: arpeggio
chord: 7
key: C
fingering: true
```
''');
        expect(result.issues.single.severity, IssueSeverity.warning);
      },
    );

    test('o jazz 3-5-7-9 só vai até uma oitava', () async {
      final result = await _read('''
```zywny-exercise
id: n5-jazz-duas
type: play-pattern
title: Jazz em duas oitavas
pattern: arpeggio
chord: 3-5-7-9
octaves: 2
```
''');
      expect(
        _messages(result).join('\n'),
        contains('`chord: 3-5-7-9` vai só até uma oitava'),
      );
    });

    test('dedilhado pedido na mão contrária só avisa', () async {
      final result = await _read('''
```zywny-exercise
id: n4-contrario
type: play-pattern
title: Contrário
pattern: scale
key: C
hand: contrary
fingering: true
```
''');
      expect(result.issues.single.severity, IssueSeverity.warning);
      expect(result.issues.single.message, contains('mão contrária'));
    });

    test(
      'o padrão de dedilhado não avisa quando o autor não o pediu',
      () async {
        final result = await _read('''
```zywny-exercise
id: n4-padrao
type: play-pattern
title: Padrão
pattern: three-note
```
''');
        expect(_messages(result), isEmpty);
      },
    );
  });
}

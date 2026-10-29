// EX22 — a leitura das melhorias de repertório: `tempo-ladder` no `pass`,
// `hand: sequence` (play-score e play-pattern), `practice: cumulative` e
// `curtain` no `play-score`, com os erros de combinação.
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
  }),
);

List<String> _messages(CourseReadResult result) => [
  for (final issue in result.issues) issue.toString(),
];

/// Um `play-score` de arquivo, com [extra] (as chaves depois de `file:`).
String _playScore(String extra, {String mode = 'realtime'}) =>
    '''
```zywny-exercise
id: n2-peca
type: play-score
title: Toque a peça
file: media/peca.musicxml
mode: $mode
$extra
```
''';

void main() {
  group('tempo-ladder: leitura', () {
    test('lê as quatro chaves no play-score em tempo real', () async {
      final result = await _read(
        _playScore(
          'pass: {accuracy: 90, tempo-ladder: {from: 60, to: 96, step: 4, back: 8}}',
        ),
      );
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayScoreSpec;
      final ladder = spec.pass.tempoLadder!;
      expect(ladder.from, 60);
      expect(ladder.to, 96);
      expect(ladder.step, 4);
      expect(ladder.back, 8);
      // Sem a escada, o `pass` não tem andamento de escada.
      expect(spec.pass.speed, 100);
    });

    test('vale no play-chart, que é sempre com tempo', () async {
      final result = await _read('''
```zywny-exercise
id: n2-grade
type: play-chart
title: Grade
chart: "|: C | Am | F | G :|"
key: C
pattern: oom-pah
bpm: 80
pass: {accuracy: 85, tempo-ladder: {from: 60, to: 80, step: 4, back: 8}}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayChartSpec;
      expect(spec.pass.tempoLadder!.to, 80);
    });

    test('não vale num tipo sem tempo', () async {
      final result = await _read('''
```zywny-exercise
id: n2-escolha
type: choice
title: Escolha
question: Qual?
options: [a, b]
answer: a
pass: {tempo-ladder: {from: 60, to: 96, step: 4, back: 8}}
```
''');
      expect(
        _messages(result).join('\n'),
        contains('`tempo-ladder` não vale em `choice`'),
      );
    });

    test('não vale junto com speed', () async {
      final result = await _read(
        _playScore(
          'pass: {speed: 80, tempo-ladder: {from: 60, to: 96, step: 4, back: 8}}',
        ),
      );
      expect(
        _messages(result).join('\n'),
        contains('`speed` não vale junto com `tempo-ladder`'),
      );
    });

    test('a meta não fica abaixo do começo', () async {
      final result = await _read(
        _playScore(
          'pass: {tempo-ladder: {from: 96, to: 60, step: 4, back: 8}}',
        ),
      );
      expect(
        _messages(result).join('\n'),
        contains('a meta (`to: 60`) fica abaixo do começo (`from: 96`)'),
      );
    });

    test('no modo espera não mede o tempo tocado', () async {
      final result = await _read(
        _playScore(
          'pass: {tempo-ladder: {from: 60, to: 96, step: 4, back: 8}}',
          mode: 'wait',
        ),
      );
      expect(
        _messages(result).join('\n'),
        contains('o modo espera não mede o tempo tocado'),
      );
    });

    test('pede as quatro chaves', () async {
      final result = await _read(
        _playScore('pass: {tempo-ladder: {from: 60, to: 96}}'),
      );
      expect(
        _messages(result).join('\n'),
        contains('falta a chave obrigatória `step`'),
      );
    });
  });

  group('hand: sequence', () {
    test('no play-score vira HandChoice.sequence', () async {
      final result = await _read(_playScore('hand: sequence'));
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(spec.hand, HandChoice.sequence);
    });

    test('no play-pattern liga handSequence e põe as duas mãos', () async {
      final result = await _read('''
```zywny-exercise
id: n2-escala
type: play-pattern
title: Escala
pattern: scale
scale: major
keys: [G]
octaves: 1
hand: sequence
mode: realtime
bpm: 72
pass: {accuracy: 90}
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayPatternSpec;
      expect(spec.handSequence, isTrue);
      expect(spec.hand, PatternHand.both);
    });

    test('a mão comum do play-pattern continua igual', () async {
      final result = await _read('''
```zywny-exercise
id: n2-escala
type: play-pattern
title: Escala
pattern: scale
scale: major
keys: [G]
octaves: 1
hand: left
bpm: 72
pass: {accuracy: 90}
```
''');
      final spec =
          result.course!.lessons.single.exercises.single as PlayPatternSpec;
      expect(spec.handSequence, isFalse);
      expect(spec.hand, PatternHand.left);
    });
  });

  group('practice: cumulative e curtain', () {
    test('practice: cumulative lê PracticeChoice.cumulative', () async {
      final result = await _read(_playScore('practice: cumulative'));
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(spec.practice, PracticeChoice.cumulative);
    });

    test('practice sem valor conhecido é erro', () async {
      final result = await _read(_playScore('practice: sobe'));
      expect(_messages(result), isNotEmpty);
    });

    test('practice não vale no play-pattern', () async {
      final result = await _read('''
```zywny-exercise
id: n2-escala
type: play-pattern
title: Escala
pattern: scale
scale: major
keys: [G]
octaves: 1
practice: cumulative
mode: realtime
bpm: 72
pass: {accuracy: 90}
```
''');
      expect(_messages(result).join('\n'), contains('`practice`'));
    });

    test('curtain padrão é false; true com tempo real', () async {
      final plain = await _read(_playScore(''));
      final spec =
          plain.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(spec.curtain, isFalse);
      expect(spec.practice, isNull);

      final curtain = await _read(_playScore('curtain: true'));
      expect(_messages(curtain), isEmpty);
      final on =
          curtain.course!.lessons.single.exercises.single as PlayScoreSpec;
      expect(on.curtain, isTrue);
    });

    test('curtain no modo espera é erro', () async {
      final result = await _read(_playScore('curtain: true', mode: 'wait'));
      expect(
        _messages(result).join('\n'),
        contains('`curtain: true` só vale com `mode: realtime`'),
      );
    });
  });
}

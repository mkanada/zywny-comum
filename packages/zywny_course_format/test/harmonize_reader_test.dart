// EX16 — o `harmonize` na leitura: os três modos, a melodia (`step` ou `file`),
// os graus, a troca e o molde, e os erros que o texto diz (o `reharmonize`
// ainda não roda, `key` com `file`, `marked` com `step`…).
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

const _xml = '<score-partwise><part id="P1"></part></score-partwise>';

String _lesson(String body) => '---\nid: um\ntitle: Um\n---\n\n$body';

Future<CourseReadResult> _read(String body) => readCourse(
  MemoryCourseFiles({
    'course.md': _course,
    'lessons/01-um.md': _lesson(body),
    'media/folclore.musicxml': _xml,
  }),
);

String _messages(CourseReadResult result) =>
    [for (final issue in result.issues) issue.toString()].join('\n');

HarmonizeSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as HarmonizeSpec;

void main() {
  group('harmonize: leitura', () {
    test('o modo degrees com a melodia gerada e os graus do autor', () async {
      final result = await _read('''
```zywny-exercise
id: n2-harmonize-graus
type: harmonize
title: Escolha os acordes
mode: degrees
melody: {step: 7b, key: G}
chords: [I, IV, V7]
change: half-bar
count: 3
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.type, ExerciseType.harmonize);
      expect(spec.mode, HarmonizeMode.degrees);
      final melody = spec.melody as StepMelody;
      expect(melody.step, '7b');
      expect(melody.key, 'G');
      expect(spec.chords, ['I', 'IV', 'V7']);
      expect(spec.change, HarmonizeChange.halfBar);
      expect(spec.count, 3);
      expect(spec.pattern, isNull, reason: 'o molde não vale com degrees');
      expect(spec.pass.accuracy, 80);
    });

    test('o modo play com o arquivo, e os padrões dos valores', () async {
      final result = await _read('''
```zywny-exercise
id: n2-harmonize-tocar
type: harmonize
title: Melodia e acordes
mode: play
melody: {file: media/folclore.musicxml}
chords: [I, IV, V7]
pattern: block
bpm: 70
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.mode, HarmonizeMode.play);
      expect((spec.melody as FileMelody).path, 'media/folclore.musicxml');
      expect(spec.change, HarmonizeChange.bar);
      expect(spec.pattern, 'block');
      expect(spec.bpm, 70);
      expect(spec.split.midi, 60);
      expect(spec.count, 1);
    });

    test('o by-ear com o molde do EX11 e a troca marcada', () async {
      final result = await _read('''
```zywny-exercise
id: n3-harmonize-ouvido
type: harmonize
title: Acompanhe de ouvido
mode: by-ear
melody: {file: media/folclore.musicxml}
chords: [I, ii, IV, V7, vi]
change: marked
pattern: oom-pah
bpm: 80
pass: {accuracy: 75}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.mode, HarmonizeMode.byEar);
      expect(spec.change, HarmonizeChange.marked);
      expect(spec.pattern, 'oom-pah');
      expect(spec.chords, ['I', 'ii', 'IV', 'V7', 'vi']);
    });

    test('os valores padrão: play, bar, block, I IV V7 e C4', () async {
      final result = await _read('''
```zywny-exercise
id: n2-minimo
type: harmonize
title: Mínimo
melody: {step: 1a}
pass: {accuracy: 80}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.mode, HarmonizeMode.play);
      expect(spec.chords, ['I', 'IV', 'V7']);
      expect(spec.change, HarmonizeChange.bar);
      expect(spec.pattern, 'block');
      expect(spec.count, 1);
    });
  });

  group('harmonize: erros', () {
    test('reharmonize e technique ainda não rodam', () async {
      final result = await _read('''
```zywny-exercise
id: n6-reharmonize
type: harmonize
title: Rearmonize
mode: reharmonize
technique: tritone-sub
melody: {file: media/folclore.musicxml}
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      expect(_messages(result), contains('ainda não roda'));
      expect(_messages(result), contains('`technique`'));
    });

    test('melody pede step ou file, nunca os dois', () async {
      final result = await _read('''
```zywny-exercise
id: n2-dois
type: harmonize
title: Dois
melody: {step: 7b, file: media/folclore.musicxml}
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      expect(_messages(result), contains('uma das duas formas'));
    });

    test('key não vale com file', () async {
      final result = await _read('''
```zywny-exercise
id: n2-tom
type: harmonize
title: Tom
melody: {file: media/folclore.musicxml, key: G}
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      expect(_messages(result), contains('o tom vem da armadura'));
    });

    test('um passo que não existe e um grau que não é grau', () async {
      final result = await _read('''
```zywny-exercise
id: n2-erros
type: harmonize
title: Erros
melody: {step: 101a}
chords: [I, Z9]
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      final text = _messages(result);
      expect(text, contains('`step` `101a` não é um passo'));
      expect(text, contains('`Z9` não é um grau'));
    });

    test('change marked pede o arquivo, e count pede a geração', () async {
      final result = await _read('''
```zywny-exercise
id: n2-marcas
type: harmonize
title: Marcas
melody: {step: 2b}
change: marked
count: 2
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      final text = _messages(result);
      expect(text, contains('`change: marked` pede uma melodia do autor'));
    });

    test('count não vale com file', () async {
      final result = await _read('''
```zywny-exercise
id: n2-contagem
type: harmonize
title: Contagem
melody: {file: media/folclore.musicxml}
count: 3
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      expect(_messages(result), contains('só vale com `step`'));
    });

    test('pattern com degrees e molde que não existe', () async {
      final result = await _read('''
```zywny-exercise
id: n2-molde
type: harmonize
title: Molde
mode: degrees
melody: {step: 3a}
pattern: block
pass: {accuracy: 80}
```
''');
      expect(result.course, isNull);
      expect(_messages(result), contains('não vale com `mode: degrees`'));

      final wrong = await _read('''
```zywny-exercise
id: n2-molde-errado
type: harmonize
title: Molde
mode: play
melody: {step: 3a}
pattern: oom-pa
pass: {accuracy: 80}
```
''');
      expect(wrong.course, isNull);
      expect(_messages(wrong), contains('não há o molde `oom-pa`'));
    });
  });
}

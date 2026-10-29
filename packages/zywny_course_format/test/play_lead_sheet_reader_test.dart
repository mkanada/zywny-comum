// EX17 — o `play-lead-sheet` na leitura: o `file` (com as cifras), o molde ou o
// estilo, o que a melodia confere (`melody`), o andamento e a mão; e os erros
// que o texto diz (sem `file`, `abc`, o tom por rodada e a base ainda não rodam,
// um estilo fora da lista que roda, `pattern` com `style`, molde desconhecido).
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
    'media/canção.musicxml': _xml,
  }),
);

String _messages(CourseReadResult result) =>
    [for (final issue in result.issues) issue.toString()].join('\n');

PlayLeadSheetSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as PlayLeadSheetSpec;

void main() {
  group('play-lead-sheet: leitura', () {
    test('o exemplo do molde: file, block, melodia conferida', () async {
      final result = await _read('''
```zywny-exercise
id: n2-lead-sheet-1
type: play-lead-sheet
title: Melodia e acordes
file: media/canção.musicxml
pattern: block
bpm: 70
pass: {accuracy: 80}
```
''');
      expect(
        result.issues.where((i) => i.isError),
        isEmpty,
        reason: _messages(result),
      );
      final spec = _spec(result);
      expect(spec.type, ExerciseType.playLeadSheet);
      expect(spec.file, 'media/canção.musicxml');
      expect(spec.pattern, 'block');
      expect(spec.style, isNull);
      expect(spec.melody, LeadMelody.check);
      expect(spec.bpm, 70);
      expect(spec.swing, isNull);
      expect(spec.split.midi, 60, reason: 'o padrão é C4');
    });

    test('o estilo 7-3 com swing e melody: free', () async {
      final result = await _read('''
```zywny-exercise
id: n5-sete-tres-embaixo
type: play-lead-sheet
title: Sete-três abaixo da melodia
file: media/canção.musicxml
style: 7-3-under-melody
melody: free
bpm: 80
swing: 62
pass: {accuracy: 80}
```
''');
      expect(
        result.issues.where((i) => i.isError),
        isEmpty,
        reason: _messages(result),
      );
      final spec = _spec(result);
      expect(spec.style, LeadStyle.sevenThreeUnderMelody);
      expect(spec.melody, LeadMelody.free);
      expect(spec.swing, 62);
      expect(spec.bpm, 80);
    });

    test('os estilos que rodam são os de LeadStyle.implemented', () {
      expect(LeadStyle.implemented, {
        LeadStyle.sevenThreeUnderMelody,
        LeadStyle.blockUnderMelody,
        LeadStyle.offBeatFill,
        LeadStyle.ballad,
        LeadStyle.stride,
      });
    });

    test('a mão de `split` é a do exercício', () async {
      final result = await _read('''
```zywny-exercise
id: n2-lead-sheet-split
type: play-lead-sheet
title: Divisão em Sol
file: media/canção.musicxml
split: G3
pass: {accuracy: 80}
```
''');
      expect(
        result.issues.where((i) => i.isError),
        isEmpty,
        reason: _messages(result),
      );
      expect(_spec(result).split.midi, 55);
    });
  });

  group('play-lead-sheet: erros', () {
    Future<String> errorsOf(String body) async {
      final result = await _read(body);
      expect(result.course, isNull, reason: 'o exercício não entra');
      return _messages(result);
    }

    test('sem file nem abc', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-sem-arquivo
type: play-lead-sheet
title: Sem arquivo
pass: {accuracy: 80}
```
''');
      expect(text, contains('precisa de `file`'));
    });

    test('abc ainda não roda', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-abc
type: play-lead-sheet
title: ABC
abc: "\\"C\\" C E G c"
pass: {accuracy: 80}
```
''');
      expect(text, contains('`abc` ainda não roda'));
    });

    test('keys, cycle, key-start e backing ainda não rodam', () async {
      for (final key in [
        'keys: [C, G]',
        'cycle: 5ths',
        'key-start: rotate',
        'backing: drums',
      ]) {
        final text = await errorsOf('''
```zywny-exercise
id: n2-tom
type: play-lead-sheet
title: Tom
file: media/canção.musicxml
$key
pass: {accuracy: 80}
```
''');
        expect(text, contains('ainda não roda'), reason: key);
      }
    });

    test('um estilo que ainda não roda diz isso', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-estilo
type: play-lead-sheet
title: Locked
file: media/canção.musicxml
style: locked-hands
pass: {accuracy: 80}
```
''');
      expect(text, contains('`style: locked-hands` ainda não roda'));
    });

    test('pattern com style', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-dois
type: play-lead-sheet
title: Dois
file: media/canção.musicxml
style: stride
pattern: block
pass: {accuracy: 80}
```
''');
      expect(text, contains('`pattern` não vale com `style`'));
    });

    test('um molde que não existe, com sugestão', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-molde
type: play-lead-sheet
title: Molde
file: media/canção.musicxml
pattern: oom-pahh
pass: {accuracy: 80}
```
''');
      expect(text, contains('não há o molde `oom-pahh`'));
      expect(text, contains('oom-pah'));
    });

    test('melody com valor desconhecido', () async {
      final text = await errorsOf('''
```zywny-exercise
id: n2-melody
type: play-lead-sheet
title: Melody
file: media/canção.musicxml
melody: sometimes
pass: {accuracy: 80}
```
''');
      expect(text, contains('sometimes'));
    });
  });
}

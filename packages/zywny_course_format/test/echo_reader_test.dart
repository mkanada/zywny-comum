// EX14 — o `echo` na leitura: as três fontes (`source:`), os padrões, o `chart`
// do `chord-tones` e os erros das chaves que não valem com `licks`.
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

String _messages(CourseReadResult result) =>
    [for (final issue in result.issues) issue.toString()].join('\n');

EchoSpec _spec(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as EchoSpec;

void main() {
  group('echo: leitura', () {
    test('lê a escala, a faixa e as frases do autor', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco-cinco-notas
type: echo
title: Repita três notas
source: {scale: major, key: G, range: G3-G5}
notes: 3
figures: [quarter, half]
measures: 2
leaps: 4
start: chord-tone
bpm: 70
swing: 67
count: 6
octave: exact
rhythm: strict
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.type, ExerciseType.echo);
      final source = spec.source as EchoScaleSource;
      expect(source.scale, ScaleKind.major);
      expect(source.key, 'G');
      expect(spec.range.from.midi, 55);
      expect(spec.range.to.midi, 79);
      expect(spec.notes, 3);
      expect(spec.figures, [Figure.quarter, Figure.half]);
      expect(spec.measures, 2);
      expect(spec.leaps, 4);
      expect(spec.start, EchoStart.chordTone);
      expect(spec.bpm, 70);
      expect(spec.swing, 67);
      expect(spec.count, 6);
      expect(spec.octave, EchoOctave.exact);
      expect(spec.rhythm, EchoRhythm.strict);
      expect(spec.pass.accuracy, 70);
    });

    test(
      'os padrões: 4 notas, uma semínima, C4-C6, o echo ouve qualquer oitava',
      () async {
        final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: Repita
source: {scale: blues, key: G}
pass: {accuracy: 70}
```
''');
        expect(_messages(result), isEmpty);
        final spec = _spec(result);
        expect(spec.notes, 4);
        expect(spec.figures, [Figure.quarter]);
        expect(spec.measures, 1);
        expect(spec.leaps, 3);
        expect(spec.start, EchoStart.tonic);
        expect(spec.bpm, 80);
        expect(spec.swing, 50);
        expect(spec.count, 8);
        expect(spec.octave, EchoOctave.any);
        expect(spec.transpose, EchoTranspose.none);
        expect(spec.rhythm, EchoRhythm.loose);
        expect(spec.split.midi, 60);
        expect(spec.hand, HandChoice.right);
        expect(spec.backing, isNull);
        expect(spec.range.from.midi, 60);
        expect(spec.range.to.midi, 84);
      },
    );

    test('chord-tones lê a grade escrita; a mão e o transpose', () async {
      final result = await _read('''
```zywny-exercise
id: n4-eco-acordes
type: echo
title: As notas do acorde
source: {chord-tones: true}
chart: "| C | G7 | C | G7 |"
transpose: cycle-5
hand: left
backing: {style: shuffle, bass: walking}
pass: {accuracy: 60}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect(spec.source, isA<EchoChordSource>());
      expect(spec.chartText, '| C | G7 | C | G7 |');
      expect(spec.transpose, EchoTranspose.cycle5);
      expect(spec.hand, HandChoice.left);
      expect(spec.backing!.style.name, 'shuffle');
      expect(spec.backing!.drums, isTrue);
    });

    test('licks lê a biblioteca, sem notas nem figuras', () async {
      final result = await _read('''
```zywny-exercise
id: n5-eco-licks
type: echo
title: O lick de II–V
source: {licks: ii-v-major}
transpose: cycle-5
bpm: 90
count: 12
pass: {accuracy: 75}
```
''');
      expect(_messages(result), isEmpty);
      final spec = _spec(result);
      expect((spec.source as EchoLickSource).library, 'ii-v-major');
      expect(spec.transpose, EchoTranspose.cycle5);
      expect(spec.count, 12);
    });

    test('backing: drums é a bateria só, sem baixo', () async {
      final result = await _read('''
```zywny-exercise
id: n3-eco-bateria
type: echo
title: Com bateria
source: {scale: major, key: C}
backing: drums
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isEmpty);
      final backing = _spec(result).backing!;
      expect(backing.drums, isTrue);
      expect(backing.bass, BackingBass.none);
    });
  });

  group('echo: erros', () {
    test('sem source é erro do campo obrigatório', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: Sem fonte
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('source'));
    });

    test('duas formas de source juntas são erro', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: Duas fontes
source: {scale: major, key: C, licks: blues-basic}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('pede uma das três formas'));
    });

    test('chord-tones sem grade é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n4-eco
type: echo
title: Sem grade
source: {chord-tones: true}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('pede a grade'));
    });

    test('notes não vale com licks', () async {
      final result = await _read('''
```zywny-exercise
id: n5-eco
type: echo
title: Notas com licks
source: {licks: blues-basic}
notes: 3
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('não vale com `licks`'));
    });

    test('key não vale com licks: o tom é o da grade, ou dó', () async {
      final result = await _read('''
```zywny-exercise
id: n5-eco
type: echo
title: Tom com licks
source: {licks: blues-basic, key: G}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('`key` só vale com `scale`'));
    });

    test('biblioteca desconhecida é erro, com sugestão', () async {
      final result = await _read('''
```zywny-exercise
id: n5-eco
type: echo
title: Biblioteca errada
source: {licks: blues-basik}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('blues-basic'));
    });

    test('faixa mal escrita é erro', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: Faixa errada
source: {scale: major, key: C, range: G5-C4}
pass: {accuracy: 70}
```
''');
      expect(_messages(result), contains('não é uma faixa de notas'));
    });

    test('hand: both não existe no echo', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: As duas mãos
source: {scale: major, key: C}
hand: both
pass: {accuracy: 70}
```
''');
      expect(_messages(result), isNot(isEmpty));
    });

    test('medidores não valem no echo', () async {
      final result = await _read('''
```zywny-exercise
id: n2-eco
type: echo
title: Com legato
source: {scale: major, key: C}
pass: {accuracy: 70, legato: 80}
```
''');
      expect(_messages(result), isNot(isEmpty));
    });
  });
}

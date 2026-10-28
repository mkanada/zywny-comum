// EX02 — o `play-chord` na leitura: as chaves, os padrões, as mensagens de erro
// de cifra, de sorteio, de inversão e de molde.
import 'package:test/test.dart';
import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_course_format/vocabulary.dart';
import 'package:zywny_music/chord.dart';
import 'package:zywny_music/chord_voicing.dart';
import 'package:zywny_music/note_name.dart';

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
  group('play-chord: leitura', () {
    test('lista fixa e sorteio, com os padrões', () async {
      final result = await _read('''
```zywny-exercise
id: n2-triades
type: play-chord
title: Toque o acorde
chords: [C, Am, F, G7]
pass: {accuracy: 80}
```

```zywny-exercise
id: n2-maiores
type: play-chord
title: Maiores e menores
chords: {qualities: [M, m], roots: random, count: 10}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();

      final fixed = specs[0] as PlayChordSpec;
      expect(fixed.type, ExerciseType.playChord);
      expect(fixed.chords, isA<FixedChords>());
      expect((fixed.chords as FixedChords).symbols, ['C', 'Am', 'F', 'G7']);
      expect(fixed.inversions, [ChordInversionChoice.any]);
      expect(fixed.voicing, isNull);
      expect(fixed.hand, ChordHand.any);
      expect(fixed.split.midi, Pitch.parse('C4').midi);
      expect(fixed.range, isNull);
      expect(fixed.strict, isTrue);
      expect(fixed.omit5, isTrue);
      expect(fixed.prompt, ChordPrompt.symbol);
      expect(fixed.voiceLeading, isNull);
      expect(fixed.pass.accuracy, 80);

      final random = specs[1] as PlayChordSpec;
      expect(random.chords, isA<RandomChords>());
      final chords = random.chords as RandomChords;
      expect(chords.qualities, ['M', 'm']);
      expect(chords.roots, isNull);
      expect(chords.whiteOnly, isFalse);
      expect(chords.count, 10);
      expect(chords.sequence, 'random');
      expect(chords.key, 'C');
    });

    test('sorteio de graus, com tom e sequência', () async {
      final result = await _read('''
```zywny-exercise
id: n5-ii-v-i
type: play-chord
title: II–V–I pelo ciclo
chords: {degrees: [ii7, V7, Imaj7], key: Bb, sequence: cycle-5, count: 2}
inversion: [root, first]
hand: left
voice-leading: 4
show: degree
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayChordSpec;
      final chords = spec.chords as DegreeChords;
      expect(chords.degrees, ['ii7', 'V7', 'Imaj7']);
      expect(chords.key, 'Bb');
      expect(chords.sequence, 'cycle-5');
      expect(chords.count, 2);
      expect(spec.inversions, [
        ChordInversionChoice.root,
        ChordInversionChoice.first,
      ]);
      expect(spec.voicing, isNull);
      expect(spec.hand, ChordHand.left);
      expect(spec.voiceLeading, 4);
      expect(spec.prompt, ChordPrompt.degree);
    });

    test('roots: white e uma lista de raízes; faixa', () async {
      final result = await _read('''
```zywny-exercise
id: a
type: play-chord
title: Brancas
chords: {qualities: [M], roots: white}
range: C3-C6
```

```zywny-exercise
id: b
type: play-chord
title: Duas raízes
chords: {qualities: [m7], roots: [C, F#]}
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      expect((specs[0] as PlayChordSpec).range!.from.midi, 48);
      expect((specs[0] as PlayChordSpec).chords, isA<RandomChords>());
      expect(
        ((specs[0] as PlayChordSpec).chords as RandomChords).whiteOnly,
        isTrue,
      );
      expect(((specs[1] as PlayChordSpec).chords as RandomChords).roots, [
        'C',
        'F#',
      ]);
    });

    test('cifra que não existe, com a linha do item', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [C, Cxyz]
```
''');
      expect(_messages(result).single, contains('`Cxyz` não é uma cifra'));
    });

    test('qualities e degrees juntos, e nenhum dos dois', () async {
      final ambos = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: {qualities: [M], degrees: [I]}
```
''');
      expect(
        _messages(ambos).single,
        contains('use `qualities` **ou** `degrees`'),
      );

      final nenhum = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: {count: 3}
```
''');
      expect(
        _messages(nenhum).single,
        contains('falta `qualities` ou `degrees`'),
      );
    });

    test('qualidade e grau desconhecidos', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: {qualities: [M, mm]}
```

```zywny-exercise
id: y
type: play-chord
title: Y
chords: {degrees: [ii7, IX]}
```
''');
      final messages = _messages(result);
      expect(messages[0], contains('qualidade `mm` desconhecida'));
      expect(messages[1], contains('`IX` não é um grau'));
    });

    test('terceira inversão só com cifra de sétima', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [C, G]
inversion: third
```
''');
      expect(_messages(result).single, contains('tríade não tem 3ª inversão'));
    });

    test('molde com inversão pedida; molde que não cabe na cifra', () async {
      final comInversao = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [G7]
voicing: 7-3
inversion: root
```
''');
      expect(
        _messages(comInversao).single,
        contains('o molde já decide a ordem das notas'),
      );

      final naoCabe = await _read('''
```zywny-exercise
id: y
type: play-chord
title: Y
chords: [C, G]
voicing: 7-3
```
''');
      expect(_messages(naoCabe).single, contains('`7-3` não cabe em `C`'));
    });

    test('molde com as duas mãos, na mão esquerda, é só aviso', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [C7]
voicing: block
hand: left
```
''');
      expect(result.issues.single.severity, IssueSeverity.warning);
      expect(_messages(result).single, contains('pede as duas mãos'));
    });

    test('faixa invertida ou mal escrita', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [C]
range: C6-C3
```
''');
      expect(_messages(result).single, contains('não é uma faixa de notas'));
    });

    test('split, strict e omit5 valem como escritos', () async {
      final result = await _read('''
```zywny-exercise
id: x
type: play-chord
title: X
chords: [C7]
hand: right
split: E4
strict: false
omit5: false
show: name
```
''');
      expect(_messages(result), isEmpty);
      final spec =
          result.course!.lessons.single.exercises.single as PlayChordSpec;
      expect(spec.split.midi, Pitch.parse('E4').midi);
      expect(spec.hand, ChordHand.right);
      expect(spec.strict, isFalse);
      expect(spec.omit5, isFalse);
      expect(spec.prompt, ChordPrompt.chordName);
    });

    test('todos os moldes do EX00 existem no zywny_music', () {
      expect(
        kVoicingShapes.values.toSet(),
        VoicingShape.values.toSet(),
        reason: 'um molde novo no zywny_music precisa do nome no formato',
      );
    });

    test('bpm e beats: o modo com tempo, beats padrão 4', () async {
      final result = await _read('''
```zywny-exercise
id: n2-com-tempo
type: play-chord
title: Com tempo
chords: [G7, C]
bpm: 60
pass: {accuracy: 80}
```

```zywny-exercise
id: n2-dois-tempos
type: play-chord
title: Dois tempos
chords: [G7, C]
bpm: 72
beats: 2
```

```zywny-exercise
id: n2-sem-tempo
type: play-chord
title: Sem tempo
chords: [G7, C]
```
''');
      expect(_messages(result), isEmpty);
      final specs = result.course!.lessons.single.exercises.toList();
      expect((specs[0] as PlayChordSpec).bpm, 60);
      expect((specs[0] as PlayChordSpec).beats, 4);
      expect((specs[1] as PlayChordSpec).bpm, 72);
      expect((specs[1] as PlayChordSpec).beats, 2);
      expect((specs[2] as PlayChordSpec).bpm, isNull);
    });

    test('beats sem bpm, e bpm com time-limit, são erros', () async {
      final result = await _read('''
```zywny-exercise
id: n2-beats-solto
type: play-chord
title: Beats sem bpm
chords: [G7, C]
beats: 2
```

```zywny-exercise
id: n2-tempo-e-limite
type: play-chord
title: Tempo e limite
chords: [G7, C]
bpm: 60
pass: {time-limit: 10}
```
''');
      final messages = _messages(result);
      expect(
        messages.any((m) => m.contains('`beats` só vale com `bpm`')),
        isTrue,
        reason: messages.join('\n'),
      );
      expect(
        messages.any(
          (m) => m.contains('`bpm` e `time-limit` não valem juntos'),
        ),
        isTrue,
        reason: messages.join('\n'),
      );
      expect(result.course, isNull);
    });

    test(
      'chord-notation do curso: fixa a grafia; sem a chave, é null',
      () async {
        final fixed = await readCourse(
          MemoryCourseFiles({
            'course.md': _course.replaceFirst(
              'lessons: [um]',
              'chord-notation: brazilian\nlessons: [um]',
            ),
            'lessons/01-um.md': _lesson('Oi.'),
          }),
        );
        expect(_messages(fixed), isEmpty);
        expect(fixed.course!.chordNotation, ChordNotation.brazilian);

        final free = await _read('Oi.');
        expect(free.course!.chordNotation, isNull);
      },
    );

    test('chord-notation com um valor que não existe é erro', () async {
      final result = await readCourse(
        MemoryCourseFiles({
          'course.md': _course.replaceFirst(
            'lessons: [um]',
            'chord-notation: alema\nlessons: [um]',
          ),
          'lessons/01-um.md': _lesson('Oi.'),
        }),
      );
      expect(result.course, isNull);
      expect(_messages(result), isNotEmpty);
    });
  });
}

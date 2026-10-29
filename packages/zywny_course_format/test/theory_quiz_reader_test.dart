// EX21 — o `theory-quiz` na leitura: os tópicos (um ou uma lista, com o da
// forma recusado com "ainda não roda"), os tons (`all`, uma lista de tônicas,
// sem `m`), o número de perguntas, a resposta (botões ou teclado, e as regras
// de cada tópico) e as qualidades dos acordes.
import 'package:test/test.dart';

import 'package:zywny_course_format/course_files.dart';
import 'package:zywny_course_format/course_model.dart';
import 'package:zywny_course_format/course_reader.dart';
import 'package:zywny_course_format/vocabulary.dart';

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

TheoryQuizSpec _only(CourseReadResult result) =>
    result.course!.lessons.single.exercises.single as TheoryQuizSpec;

/// Um exercício de teoria com o corpo [extra] (as chaves a mais, linha a linha).
String _exercise(String extra) =>
    '```zywny-exercise\nid: n1-teoria\ntype: theory-quiz\ntitle: Teoria\n'
    '$extra\n```\n';

void main() {
  group('theory-quiz: o básico', () {
    test(
      'a lista de tópicos, e os padrões de tons, perguntas e resposta',
      () async {
        final result = await _read(
          _exercise(
            'topics: [relative-minor, relative-major]\n'
            'pass: {accuracy: 80, time-limit: 15}',
          ),
        );
        expect(_messages(result), isEmpty);
        final spec = _only(result);
        expect(spec.type, ExerciseType.theoryQuiz);
        expect(spec.topics, [
          TheoryTopic.relativeMinor,
          TheoryTopic.relativeMajor,
        ]);
        expect(spec.keys, ['C', 'G', 'F'], reason: 'o padrão');
        expect(spec.count, 10, reason: 'o padrão');
        expect(spec.answer, TheoryAnswer.buttons, reason: 'o padrão');
        expect(spec.qualities, ['M', 'm'], reason: 'o padrão');
        expect(spec.pass.timeLimit, 15, reason: 'o time-limit vale aqui');
      },
    );

    test('um tópico escrito sozinho também vale', () async {
      final result = await _read(_exercise('topics: parallel\nkeys: [Eb, Bb]'));
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.topics, [TheoryTopic.parallel]);
      expect(spec.keys, ['Eb', 'Bb']);
    });

    test('`keys: all` são os 12 tons, com a grafia da lista', () async {
      final result = await _read(
        _exercise('topics: key-signature\nkeys: all\ncount: 40'),
      );
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.keys, kTheoryAllKeys);
      expect(spec.keys, hasLength(12));
      expect(spec.count, 40);
    });

    test('as qualidades dos acordes, com `answer: keyboard`', () async {
      final result = await _read(
        _exercise(
          'topics: [chord-tones, scale-degree]\n'
          'answer: keyboard\n'
          'qualities: [M, m7, dim]',
        ),
      );
      expect(_messages(result), isEmpty);
      final spec = _only(result);
      expect(spec.answer, TheoryAnswer.keyboard);
      expect(spec.qualities, ['M', 'm7', 'dim']);
    });
  });

  group('theory-quiz: os erros', () {
    test('o tópico da forma ainda não roda', () async {
      final result = await _read(_exercise('topics: [form-template]'));
      expect(_messages(result), contains('ainda não roda'));
    });

    test('um tópico que não existe, com a sugestão', () async {
      final result = await _read(_exercise('topics: [sharps-ordem]'));
      expect(_messages(result), contains('sharps-order'));
    });

    test('um tom menor em `keys` (o modo vem do tópico)', () async {
      final result = await _read(
        _exercise('topics: relative-minor\nkeys: [Am, C]'),
      );
      expect(_messages(result), contains('é um tom menor'));
    });

    test('`keys: random` não vale', () async {
      final result = await _read(
        _exercise('topics: relative-minor\nkeys: random'),
      );
      expect(_messages(result), contains('keys: random'));
    });

    test('`answer: keyboard` sem tópico de nota ou acorde', () async {
      final result = await _read(
        _exercise('topics: [key-signature]\nanswer: keyboard'),
      );
      expect(_messages(result), contains('`answer: keyboard` pede'));
    });

    test('`interval-build` com botões', () async {
      final result = await _read(_exercise('topics: [interval-build]'));
      expect(_messages(result), contains('só se responde no teclado'));
    });

    test('`interval-build` no teclado passa', () async {
      final result = await _read(
        _exercise('topics: [interval-build, circle-next]\nanswer: keyboard'),
      );
      expect(_messages(result), isEmpty);
    });

    test('`qualities` sem tópico de acorde', () async {
      final result = await _read(
        _exercise('topics: [scale-degree]\nqualities: [M]'),
      );
      expect(_messages(result), contains('`qualities` só vale'));
    });

    test('uma qualidade fora da lista (a 9ª não entra)', () async {
      final result = await _read(
        _exercise('topics: [chord-tones]\nqualities: [9]'),
      );
      expect(_messages(result), contains('não é uma qualidade'));
    });

    test('o 7 sem aspas é a qualidade de sétima', () async {
      final result = await _read(
        _exercise('topics: [chord-from-staff]\nqualities: [M, 7, m7]'),
      );
      expect(_messages(result), isEmpty);
      expect(_only(result).qualities, ['M', '7', 'm7']);
    });

    test('`count` fora de 1 a 40', () async {
      final result = await _read(_exercise('topics: [circle-next]\ncount: 41'));
      expect(_messages(result), contains('count'));
    });
  });
}

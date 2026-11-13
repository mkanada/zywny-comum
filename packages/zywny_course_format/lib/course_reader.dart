import 'dart:convert';

import 'package:zywny_music/chord.dart';

import 'course_files.dart';
import 'course_issue.dart';
import 'course_model.dart';
import 'field_reader.dart';
import 'lesson_scanner.dart';
import 'mark_parser.dart';
import 'text_check.dart';
import 'vocabulary.dart';

export 'course_issue.dart' show CourseIssue, CourseReadResult, IssueSeverity;

const _courseFile = 'course.md';

/// Lê e valida um curso inteiro. Junta **todos** os problemas (o professor
/// corrige tudo de uma vez); só desiste de um arquivo cujo front matter não
/// se lê. `course` só vem se não houver nenhum erro (avisos não contam).
Future<CourseReadResult> readCourse(CourseFiles files) async {
  final issues = <CourseIssue>[];
  final existing = (await files.list()).toSet();

  if (!existing.contains(_courseFile)) {
    FileIssues(
      _courseFile,
      issues,
    ).error(1, 'Falta o arquivo `course.md` na raiz do curso.');
    return CourseReadResult(null, issues);
  }

  final head = await _readCourseHead(files, existing, issues);
  final read = await _readLessons(files, existing, issues);
  if (head != null) {
    _LessonListCheck(head, read.lessons, read.unreadable, issues).run();
  }
  _checkExerciseIds(read.lessons.values, issues);

  issues.sort();
  final hasErrors = issues.any((i) => i.isError);
  if (hasErrors || head == null) return CourseReadResult(null, issues);
  final ordered = [for (final id in head.lessonIds) read.lessons[id]!.lesson];
  return CourseReadResult(
    Course(
      format: head.format,
      id: head.id,
      title: head.title,
      author: head.author,
      version: head.version,
      intro: head.intro,
      lessons: ordered,
      chordNotation: head.chordNotation,
    ),
    issues,
  );
}

/// As lições de `lessons/`, na ordem dos nomes, e quantas não se leram.
Future<({Map<String, _ParsedLesson> lessons, int unreadable})> _readLessons(
  CourseFiles files,
  Set<String> existing,
  List<CourseIssue> issues,
) async {
  final lessonFiles = [
    for (final path in existing)
      if (RegExp(r'^lessons/[^/]+\.md$').hasMatch(path)) path,
  ]..sort();
  final lessons = <String, _ParsedLesson>{};
  var unreadable = 0;
  for (final path in lessonFiles) {
    final lesson = await _readLesson(files, path, existing, issues);
    if (lesson == null) {
      unreadable++;
    } else {
      _addLesson(lessons, lesson, issues);
    }
  }
  return (lessons: lessons, unreadable: unreadable);
}

/// Põe [lesson] em [lessons]; se o `id` já existe, o erro vai nas duas.
void _addLesson(
  Map<String, _ParsedLesson> lessons,
  _ParsedLesson lesson,
  List<CourseIssue> sink,
) {
  final other = lessons[lesson.lesson.id];
  if (other == null) {
    lessons[lesson.lesson.id] = lesson;
    return;
  }
  FileIssues(lesson.file, sink).error(
    lesson.idLine,
    'id de lição repetido `${lesson.lesson.id}` '
    '(também em ${other.file}:${other.idLine}).',
  );
  FileIssues(other.file, sink).error(
    other.idLine,
    'id de lição repetido `${lesson.lesson.id}` '
    '(também em ${lesson.file}:${lesson.idLine}).',
  );
}

class _CourseHead {
  _CourseHead({
    required this.format,
    required this.id,
    required this.title,
    required this.author,
    required this.version,
    required this.intro,
    required this.lessonIds,
    required this.lessonLines,
    required this.lessonsLine,
    this.chordNotation,
  });

  /// `chord-notation:` do curso; `null` segue a configuração do app.
  final ChordNotation? chordNotation;

  final int format;
  final String id;
  final String title;
  final String author;
  final String version;
  final String intro;
  final List<String> lessonIds;
  final List<int> lessonLines;
  final int lessonsLine;
}

class _ParsedLesson {
  _ParsedLesson(
    this.file,
    this.lesson,
    this.idLine,
    this.requiresLines,
    this.requiresLine,
  );

  final String file;
  final Lesson lesson;
  final int idLine;

  /// Linha de cada item de `requires`, na mesma ordem.
  final List<int> requiresLines;
  final int requiresLine;
}

Future<String?> _readText(
  CourseFiles files,
  String path,
  FileIssues issues,
) async {
  try {
    return utf8.decode(await files.read(path));
  } on FormatException {
    issues.error(1, 'O arquivo não está em UTF-8.');
    return null;
  }
}

Future<_CourseHead?> _readCourseHead(
  CourseFiles files,
  Set<String> existing,
  List<CourseIssue> sink,
) async {
  final issues = FileIssues(_courseFile, sink);
  final text = await _readText(files, _courseFile, issues);
  if (text == null) return null;
  final scanned = scanLessonFile(text, onError: issues.error);
  final front = scanned.front;
  if (front == null) return null;

  final reader = FieldReader(issues, existing);
  final map = reader.parseMap(front.yaml, front.firstLine, blockLine: 1);
  if (map == null) return null;
  final fields = reader.read(
    map,
    kCourseKeys,
    FieldBlock(
      firstLine: front.firstLine,
      blockLine: 1,
      where: 'no front matter do curso',
    ),
  );

  final format = fields.get<int>('format');
  if (format != null && format > kCourseFormat) {
    issues.error(
      fields.lineOf('format'),
      'Este curso pede uma versão mais nova do zywny.',
    );
    return null;
  }
  if (fields.failed) return null;

  final intro = _introOf(scanned.segments, existing, issues);

  return _CourseHead(
    format: format!,
    id: fields.get<String>('id')!,
    title: fields.get<String>('title')!,
    author: fields.get<String>('author')!,
    version: fields.get<String>('version')!,
    intro: intro,
    lessonIds: fields.get<List<Object>>('lessons')!.cast<String>(),
    lessonLines: fields.itemLines['lessons']!,
    lessonsLine: fields.lineOf('lessons'),
    chordNotation: _notationOf(fields.get<String>('chord-notation')),
  );
}

/// O corpo de `course.md` é só a apresentação: texto, sem marcas.
String _introOf(
  List<Segment> segments,
  Set<String> existing,
  FileIssues issues,
) {
  final intro = StringBuffer();
  for (final segment in segments) {
    switch (segment) {
      case TextSegment():
        checkMarkdownText(segment, issues, existing);
        if (intro.isNotEmpty) intro.write('\n\n');
        intro.write(segment.text);
      case MarkSegment():
        issues.error(
          segment.line,
          'as marcas `zywny-…` só valem nas lições, não em `course.md`.',
        );
    }
  }
  return intro.toString();
}

/// A grafia de `chord-notation:` (já conferida pelo vocabulário); `null` se o
/// curso não fixa uma.
ChordNotation? _notationOf(String? wire) =>
    wire == null ? null : ChordNotation.values.byName(wire);

Future<_ParsedLesson?> _readLesson(
  CourseFiles files,
  String path,
  Set<String> existing,
  List<CourseIssue> sink,
) async {
  final issues = FileIssues(path, sink);
  final text = await _readText(files, path, issues);
  if (text == null) return null;
  final scanned = scanLessonFile(text, onError: issues.error);
  final front = scanned.front;
  if (front == null) return null;

  final reader = FieldReader(issues, existing);
  final map = reader.parseMap(front.yaml, front.firstLine, blockLine: 1);
  if (map == null) return null;
  final fields = reader.read(
    map,
    kLessonKeys,
    FieldBlock(
      firstLine: front.firstLine,
      blockLine: 1,
      where: 'no front matter da lição',
    ),
  );

  final blocks = <LessonBlock>[];
  for (final segment in scanned.segments) {
    switch (segment) {
      case TextSegment():
        checkMarkdownText(segment, issues, existing);
        blocks.add(TextBlock(segment.text, segment.line));
      case MarkSegment():
        final block = parseMark(segment, issues, existing);
        if (block != null) blocks.add(block);
    }
  }
  if (fields.failed) return null;

  return _ParsedLesson(
    path,
    Lesson(
      id: fields.get<String>('id')!,
      title: fields.get<String>('title')!,
      requires: fields.get<List<Object>>('requires')?.cast<String>() ?? [],
      fileName: path,
      blocks: blocks,
    ),
    fields.lineOf('id'),
    fields.itemLines['requires'] ?? const [],
    fields.lineOf('requires'),
  );
}

/// As conferências de `course.md` × `lessons/` e do `requires` de cada lição
/// (existência, ciclo, ordem). Elas dividem a posição de cada id em `lessons`,
/// as arestas do `requires` e o que já está num ciclo.
class _LessonListCheck {
  _LessonListCheck(this.head, this.lessons, this.unreadable, this.sink);

  final _CourseHead head;
  final Map<String, _ParsedLesson> lessons;

  /// Arquivos de `lessons/` que não se leram: o erro deles já explica a falta.
  final int unreadable;
  final List<CourseIssue> sink;

  /// Posição de cada id em `lessons` de `course.md`.
  final _order = <String, int>{};

  /// Os `requires` que existem de cada lição: (id citado, linha).
  final _edges = <String, List<(String, int)>>{};

  /// Pares `de>para` de um ciclo: a ordem deles já deu o seu erro.
  final _inCycle = <String>{};
  final _state = <String, int>{};
  final _stack = <String>[];

  void run() {
    _checkLessonList();
    _readRequires();
    _findCycles();
    _checkRequiresOrder();
  }

  /// `lessons` de `course.md` × os arquivos lidos.
  void _checkLessonList() {
    final course = FileIssues(_courseFile, sink);
    for (var i = 0; i < head.lessonIds.length; i++) {
      final id = head.lessonIds[i];
      final line = head.lessonLines[i];
      if (_order.containsKey(id)) {
        course.error(line, 'a lição `$id` aparece duas vezes em `lessons`.');
        continue;
      }
      _order[id] = i;
      // Com um arquivo ilegível, o erro dele já explica a falta.
      if (!lessons.containsKey(id) && unreadable == 0) {
        course.error(
          line,
          'a lição `$id` não tem arquivo em `lessons/` (o `id` do front '
          'matter precisa ser `$id`).',
        );
      }
    }
    for (final entry in lessons.entries) {
      if (!_order.containsKey(entry.key)) {
        FileIssues(entry.value.file, sink).warning(
          entry.value.idLine,
          'a lição `${entry.key}` não está em `lessons` de `course.md` e não '
          'entra no curso.',
        );
      }
    }
  }

  /// O `requires` de cada lição: o que cita uma lição inexistente dá erro; o
  /// resto vira aresta.
  void _readRequires() {
    for (final entry in lessons.entries) {
      final parsed = entry.value;
      final file = FileIssues(parsed.file, sink);
      final list = <(String, int)>[];
      for (var i = 0; i < parsed.lesson.requires.length; i++) {
        final target = parsed.lesson.requires[i];
        final line = i < parsed.requiresLines.length
            ? parsed.requiresLines[i]
            : parsed.requiresLine;
        if (!lessons.containsKey(target)) {
          file.error(
            line,
            '`requires` cita a lição `$target`, que não existe no curso.',
          );
          continue;
        }
        list.add((target, line));
      }
      _edges[entry.key] = list;
    }
  }

  /// Ciclos no `requires`, por busca em profundidade.
  void _findCycles() {
    for (final id in [
      ...head.lessonIds.where(lessons.containsKey),
      ...lessons.keys,
    ]) {
      if (_state[id] == null) _visit(id);
    }
  }

  void _visit(String id) {
    _state[id] = 1;
    _stack.add(id);
    for (final (target, line) in _edges[id] ?? const <(String, int)>[]) {
      if (_state[target] == 1) {
        _reportCycle(id, target, line);
      } else if (_state[target] == null) {
        _visit(target);
      }
    }
    _stack.removeLast();
    _state[id] = 2;
  }

  void _reportCycle(String id, String target, int line) {
    final cycle = [..._stack.sublist(_stack.indexOf(target)), target];
    FileIssues(
      lessons[id]!.file,
      sink,
    ).error(line, '`requires` forma um ciclo: ${cycle.join(' → ')}.');
    for (var i = 0; i < cycle.length - 1; i++) {
      _inCycle.add('${cycle[i]}>${cycle[i + 1]}');
    }
  }

  /// Só valem lições anteriores na ordem de `lessons`; as arestas de ciclo
  /// ficam de fora.
  void _checkRequiresOrder() {
    for (final entry in _edges.entries) {
      final from = _order[entry.key];
      for (final (target, line) in entry.value) {
        final to = _order[target];
        if (from == null ||
            to == null ||
            _inCycle.contains('${entry.key}>$target')) {
          continue;
        }
        if (to >= from) {
          FileIssues(lessons[entry.key]!.file, sink).error(
            line,
            '`requires` cita a lição `$target`, que vem depois na ordem de '
            '`lessons`: só valem lições anteriores.',
          );
        }
      }
    }
  }
}

/// Id de exercício único no curso inteiro: erro nas duas linhas.
void _checkExerciseIds(
  Iterable<_ParsedLesson> lessons,
  List<CourseIssue> sink,
) {
  final seen = <String, List<(String, int)>>{};
  for (final parsed in lessons) {
    for (final spec in parsed.lesson.exercises) {
      seen.putIfAbsent(spec.id, () => []).add((parsed.file, spec.line));
    }
  }
  for (final entry in seen.entries) {
    if (entry.value.length < 2) continue;
    for (final (file, line) in entry.value) {
      final others = [
        for (final (f, l) in entry.value)
          if (f != file || l != line) '$f:$l',
      ];
      FileIssues(file, sink).error(
        line,
        'id de exercício repetido `${entry.key}` '
        '(também em ${others.join(', ')}).',
      );
    }
  }
}

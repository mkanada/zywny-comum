import 'package:meta/meta.dart';

import 'course_model.dart';

enum IssueSeverity { error, warning }

/// Um problema achado ao ler um curso, com o lugar exato para o autor.
@immutable
class CourseIssue implements Comparable<CourseIssue> {
  const CourseIssue({
    required this.severity,
    required this.file,
    required this.line,
    required this.message,
  });

  final IssueSeverity severity;

  /// Caminho relativo à raiz do curso (`lessons/02-pauta.md`).
  final String file;

  /// Linha (base 1) no arquivo.
  final int line;

  /// Em português, pronta para o professor.
  final String message;

  bool get isError => severity == IssueSeverity.error;

  /// `arquivo:linha: erro|aviso: mensagem` — a linha que o validador imprime.
  @override
  String toString() => '$file:$line: ${isError ? 'erro' : 'aviso'}: $message';

  @override
  int compareTo(CourseIssue other) {
    final byFile = file.compareTo(other.file);
    if (byFile != 0) return byFile;
    final byLine = line.compareTo(other.line);
    if (byLine != 0) return byLine;
    final bySeverity = severity.index.compareTo(other.severity.index);
    if (bySeverity != 0) return bySeverity;
    return message.compareTo(other.message);
  }
}

/// O que [readCourse] devolve: o curso (só se não houver erro) e todos os
/// problemas, ordenados por arquivo e linha.
@immutable
class CourseReadResult {
  const CourseReadResult(this.course, this.issues);

  final Course? course;
  final List<CourseIssue> issues;

  bool get hasErrors => issues.any((issue) => issue.isError);
}

/// Quem recebe os problemas de **um** arquivo.
class FileIssues {
  FileIssues(this.file, this._sink);

  final String file;
  final List<CourseIssue> _sink;

  /// Quantos erros este arquivo já tem — para saber se um trecho falhou.
  int get errorCount => _sink.where((i) => i.isError && i.file == file).length;

  void error(int line, String message) => _sink.add(
    CourseIssue(
      severity: IssueSeverity.error,
      file: file,
      line: line < 1 ? 1 : line,
      message: message,
    ),
  );

  void warning(int line, String message) => _sink.add(
    CourseIssue(
      severity: IssueSeverity.warning,
      file: file,
      line: line < 1 ? 1 : line,
      message: message,
    ),
  );
}

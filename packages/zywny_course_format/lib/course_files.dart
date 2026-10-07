import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// De onde o leitor tira os arquivos de um curso: caminhos relativos à raiz
/// do curso, sempre com `/` (`course.md`, `lessons/01-x.md`, `media/a.png`).
///
/// Não há disco nem rede aqui: a pasta (`directory_course_files.dart`), o
/// pacote `.zywny` ([ZipCourseFiles]) e os assets do app são só maneiras de
/// preencher esta interface.
abstract class CourseFiles {
  /// Nome para mensagens ("iniciacao", "curso.zywny").
  String get label;

  /// Todos os arquivos, por caminho relativo.
  Future<List<String>> list();

  Future<Uint8List> read(String path);
}

/// Arquivos em memória, para testes. Os valores são `String` (UTF-8) ou
/// `Uint8List`.
class MemoryCourseFiles implements CourseFiles {
  MemoryCourseFiles(Map<String, Object> files, {this.label = 'memória'})
    : _files = {
        for (final entry in files.entries)
          entry.key: entry.value is String
              ? Uint8List.fromList(utf8.encode(entry.value as String))
              : entry.value as Uint8List,
      };

  final Map<String, Uint8List> _files;

  @override
  final String label;

  @override
  Future<List<String>> list() async => _files.keys.toList()..sort();

  @override
  Future<Uint8List> read(String path) async {
    final bytes = _files[path];
    if (bytes == null) throw ArgumentError('Arquivo ausente: $path');
    return bytes;
  }
}

/// Os arquivos de um zip (o pacote de curso do I04).
class ZipCourseFiles implements CourseFiles {
  ZipCourseFiles(Uint8List bytes, {this.label = 'pacote'})
    : _archive = ZipDecoder().decodeBytes(bytes);

  final Archive _archive;

  @override
  final String label;

  @override
  Future<List<String>> list() async => [
    for (final file in _archive.files)
      if (file.isFile) file.name,
  ]..sort();

  @override
  Future<Uint8List> read(String path) async {
    final file = _archive.findFile(path);
    if (file == null || !file.isFile) {
      throw ArgumentError('Arquivo ausente: $path');
    }
    return file.content;
  }
}

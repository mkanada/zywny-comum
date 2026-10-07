import 'dart:io';
import 'dart:typed_data';

import 'course_files.dart';

/// Os arquivos de uma pasta de curso (comando de linha e modo nativo).
/// Ignora o que começa com ponto (`.git`, `.DS_Store`).
class DirectoryCourseFiles implements CourseFiles {
  DirectoryCourseFiles(this.root);

  final Directory root;

  @override
  String get label => root.path.split(Platform.pathSeparator).last;

  @override
  Future<List<String>> list() async {
    final base = root.absolute.path;
    final result = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.absolute.path
          .substring(base.length)
          .replaceAll(Platform.pathSeparator, '/')
          .replaceFirst(RegExp(r'^/+'), '');
      if (relative.split('/').any((part) => part.startsWith('.'))) continue;
      result.add(relative);
    }
    return result..sort();
  }

  @override
  Future<Uint8List> read(String path) =>
      File('${root.path}/$path').readAsBytes();
}

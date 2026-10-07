import 'course_issue.dart';
import 'field_reader.dart';
import 'lesson_scanner.dart';
import 'vocabulary.dart';

final _inlineCode = RegExp(r'`[^`\n]*`');
final _image = RegExp(
  r'''!\[[^\]]*\]\(\s*([^)\s]*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)''',
);
final _link = RegExp(
  r'''\[[^\]]*\]\(\s*([^)\s]*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)''',
);
final _html = RegExp(r'<(?:/?[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?|!--.*?)>');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Confere o texto markdown de [segment]: imagens da pasta (existem, com
/// extensão aceita, sem caminho de fora), links só `https://` e HTML (que
/// aparece como texto — aviso).
void checkMarkdownText(
  TextSegment segment,
  FileIssues issues,
  Set<String> existing,
) {
  String? fenceMark;
  var fenceLength = 0;
  final lines = splitLines(segment.text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fileLine = segment.line + i;
    final fence = _fence.firstMatch(line);
    if (fenceMark != null) {
      final trimmed = line.trim();
      if (trimmed.startsWith(fenceMark * fenceLength) &&
          trimmed.replaceAll(fenceMark, '').isEmpty) {
        fenceMark = null;
      }
      continue;
    }
    if (fence != null) {
      fenceMark = fence.group(1)![0];
      fenceLength = fence.group(1)!.length;
      continue;
    }

    // Código em linha é texto de exemplo: não confere nada dentro dele.
    var text = line.replaceAllMapped(
      _inlineCode,
      (m) => ' ' * m.group(0)!.length,
    );

    for (final match in _image.allMatches(text)) {
      final path = match.group(1)!;
      final problem = coursePathProblem(
        path,
        existing,
        extensions: kImageExtensions,
      );
      if (problem != null) issues.error(fileLine, 'imagem: $problem');
    }
    text = text.replaceAllMapped(_image, (m) => ' ' * m.group(0)!.length);

    for (final match in _link.allMatches(text)) {
      final target = match.group(1)!;
      if (!target.startsWith('https://')) {
        issues.error(
          fileLine,
          'o link `$target` não vale: links do texto só podem ser '
          '`https://…`.',
        );
      }
    }
    if (_html.hasMatch(text)) {
      issues.warning(fileLine, 'HTML não é interpretado e aparece como texto.');
    }
  }
}

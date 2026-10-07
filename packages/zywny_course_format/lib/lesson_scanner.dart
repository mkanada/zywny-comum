import 'package:meta/meta.dart';

/// O front matter de um arquivo: o YAML entre as duas linhas `---`.
@immutable
class FrontMatter {
  const FrontMatter(this.yaml, this.firstLine);

  final String yaml;

  /// Linha (base 1) do arquivo em que começa a primeira linha de [yaml].
  final int firstLine;
}

/// Um pedaço do corpo: texto markdown ou uma marca ` ```zywny-… `.
sealed class Segment {
  const Segment(this.line);

  /// Texto: linha da primeira linha. Marca: linha da abertura (` ```zywny-… `).
  final int line;
}

class TextSegment extends Segment {
  const TextSegment(this.text, super.line);

  final String text;
}

class MarkSegment extends Segment {
  const MarkSegment(this.name, this.body, super.line);

  /// O que vem depois de `zywny-` (`score`, `exercise`…).
  final String name;
  final String body;

  /// Linha do arquivo em que começa a primeira linha de [body].
  int get bodyLine => line + 1;
}

@immutable
class ScannedFile {
  const ScannedFile(this.front, this.segments);

  final FrontMatter? front;
  final List<Segment> segments;
}

final _markOpen = RegExp(r'^```zywny-([A-Za-z0-9_-]*)[ \t]*$');
final _markClose = RegExp(r'^```[ \t]*$');
final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

/// Normaliza quebras de linha e tira o BOM.
List<String> splitLines(String text) {
  final clean = text.startsWith('﻿') ? text.substring(1) : text;
  return clean.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

/// Corta um arquivo `.md` em front matter, texto e marcas, **antes** do
/// markdown ver o texto: é assim que cada marca guarda a linha em que abre
/// (o AST do markdown não guarda números de linha).
///
/// Cercas comuns (` ``` ` e ` ```` ` com ou sem linguagem, e `~~~`) são
/// rastreadas: um ` ```zywny-… ` escrito dentro de um bloco de código de
/// exemplo **não** vira marca. [onError] recebe (linha, mensagem).
ScannedFile scanLessonFile(
  String text, {
  required void Function(int line, String message) onError,
}) {
  final lines = splitLines(text);
  FrontMatter? front;
  var start = 0;

  if (lines.first.trimRight() == '---') {
    final close = lines.indexWhere((l) => l.trimRight() == '---', 1);
    if (close < 0) {
      onError(
        1,
        'O front matter começa em `---`, mas não há outro `---` '
        'para fechá-lo.',
      );
      return const ScannedFile(null, []);
    }
    front = FrontMatter(lines.sublist(1, close).join('\n'), 2);
    start = close + 1;
  } else {
    onError(
      1,
      'O arquivo precisa começar pelo front matter: uma linha `---`, as '
      'chaves e outra linha `---`.',
    );
  }

  final segments = <Segment>[];
  final buffer = <String>[];
  var bufferStart = start;
  String? fenceMark;
  var fenceLength = 0;

  void flushText() {
    var first = 0;
    var last = buffer.length;
    while (first < last && buffer[first].trim().isEmpty) {
      first++;
    }
    while (last > first && buffer[last - 1].trim().isEmpty) {
      last--;
    }
    if (first < last) {
      segments.add(
        TextSegment(
          buffer.sublist(first, last).join('\n'),
          bufferStart + first + 1,
        ),
      );
    }
    buffer.clear();
  }

  var i = start;
  while (i < lines.length) {
    final line = lines[i];
    if (fenceMark != null) {
      buffer.add(line);
      final trimmed = line.trimRight().trimLeft();
      if (trimmed.startsWith(fenceMark * fenceLength) &&
          trimmed.replaceAll(fenceMark, '').isEmpty) {
        fenceMark = null;
      }
      i++;
      continue;
    }
    final mark = _markOpen.firstMatch(line);
    if (mark != null) {
      flushText();
      final name = mark.group(1)!;
      final openLine = i + 1;
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && !_markClose.hasMatch(lines[j])) {
        body.add(lines[j]);
        j++;
      }
      if (j >= lines.length) {
        onError(
          openLine,
          'A marca `zywny-$name` não foi fechada: falta uma linha só com '
          'três crases (```).',
        );
        i = lines.length;
      } else {
        segments.add(MarkSegment(name, body.join('\n'), openLine));
        i = j + 1;
      }
      bufferStart = i;
      continue;
    }
    final fence = _fenceOpen.firstMatch(line);
    if (fence != null) {
      fenceMark = fence.group(1)![0];
      fenceLength = fence.group(1)!.length;
    }
    if (buffer.isEmpty) bufferStart = i;
    buffer.add(line);
    i++;
  }
  flushText();
  return ScannedFile(front, segments);
}

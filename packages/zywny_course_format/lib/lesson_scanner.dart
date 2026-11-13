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
  final head = _frontOf(lines, onError);
  if (head == null) return const ScannedFile(null, []);
  final scanner = _Scanner(lines, onError)..run(head.start);
  return ScannedFile(head.front, scanner.segments);
}

/// O front matter de [lines] e a linha em que o corpo começa. `null` se o
/// front matter não fecha (o erro já foi dado: não há o que cortar).
({FrontMatter? front, int start})? _frontOf(
  List<String> lines,
  void Function(int line, String message) onError,
) {
  if (lines.first.trimRight() != '---') {
    onError(
      1,
      'O arquivo precisa começar pelo front matter: uma linha `---`, as '
      'chaves e outra linha `---`.',
    );
    return (front: null, start: 0);
  }
  final close = lines.indexWhere((l) => l.trimRight() == '---', 1);
  if (close < 0) {
    onError(
      1,
      'O front matter começa em `---`, mas não há outro `---` '
      'para fechá-lo.',
    );
    return null;
  }
  return (
    front: FrontMatter(lines.sublist(1, close).join('\n'), 2),
    start: close + 1,
  );
}

/// O corte do corpo: o texto em curso, a cerca de código aberta e os
/// segmentos prontos (em [segments]).
class _Scanner {
  _Scanner(this._lines, this._onError);

  final List<String> _lines;
  final void Function(int line, String message) _onError;
  final segments = <Segment>[];
  final _buffer = <String>[];
  var _bufferStart = 0;
  String? _fenceMark;
  var _fenceLength = 0;

  /// Corta as linhas a partir de [start].
  void run(int start) {
    _bufferStart = start;
    var i = start;
    while (i < _lines.length) {
      final line = _lines[i];
      if (_fenceMark != null) {
        _inFence(line);
        i++;
        continue;
      }
      final mark = _markOpen.firstMatch(line);
      if (mark != null) {
        i = _mark(mark.group(1)!, i);
        continue;
      }
      final fence = _fenceOpen.firstMatch(line);
      if (fence != null) {
        _fenceMark = fence.group(1)![0];
        _fenceLength = fence.group(1)!.length;
      }
      if (_buffer.isEmpty) _bufferStart = i;
      _buffer.add(line);
      i++;
    }
    _flushText();
  }

  /// Dentro de uma cerca a linha é texto; a cerca fecha com a mesma marca e
  /// pelo menos o mesmo tamanho.
  void _inFence(String line) {
    _buffer.add(line);
    final mark = _fenceMark!;
    final trimmed = line.trimRight().trimLeft();
    if (trimmed.startsWith(mark * _fenceLength) &&
        trimmed.replaceAll(mark, '').isEmpty) {
      _fenceMark = null;
    }
  }

  /// A marca `zywny-…` que abre na linha [i] (índice); devolve a linha
  /// seguinte a ela.
  int _mark(String name, int i) {
    _flushText();
    final openLine = i + 1;
    var j = i + 1;
    while (j < _lines.length && !_markClose.hasMatch(_lines[j])) {
      j++;
    }
    if (j >= _lines.length) {
      _onError(
        openLine,
        'A marca `zywny-$name` não foi fechada: falta uma linha só com '
        'três crases (```).',
      );
      _bufferStart = _lines.length;
      return _lines.length;
    }
    segments.add(
      MarkSegment(name, _lines.sublist(i + 1, j).join('\n'), openLine),
    );
    _bufferStart = j + 1;
    return j + 1;
  }

  /// Fecha o texto em curso (sem as linhas em branco das pontas) como um
  /// segmento.
  void _flushText() {
    var first = 0;
    var last = _buffer.length;
    while (first < last && _buffer[first].trim().isEmpty) {
      first++;
    }
    while (last > first && _buffer[last - 1].trim().isEmpty) {
      last--;
    }
    if (first < last) {
      segments.add(
        TextSegment(
          _buffer.sublist(first, last).join('\n'),
          _bufferStart + first + 1,
        ),
      );
    }
    _buffer.clear();
  }
}

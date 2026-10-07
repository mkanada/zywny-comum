import 'package:yaml/yaml.dart';

import 'abc_limits.dart';
import 'course_issue.dart';
import 'course_model.dart';

import 'package:zywny_music/note_name.dart';

import 'suggest.dart';
import 'vocabulary.dart';

final _idPattern = RegExp(kIdPattern);
final _measurePattern = RegExp(r'^(\d+)(?:-(\d+))?$');
final _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');

/// Os valores já lidos de um bloco YAML (front matter, marca ou sub-mapa),
/// com a linha de cada chave para os erros seguintes.
class Fields {
  Fields(this.blockLine);

  /// Linha da abertura do bloco; vale para o que não tem linha própria.
  final int blockLine;
  final Map<String, Object?> values = {};
  final Map<String, int> lines = {};

  /// Linha de cada item de uma lista (`lessons`, `requires`, `options`…).
  final Map<String, List<int>> itemLines = {};

  /// Algum erro de forma (chave, tipo, valor, obrigatória) neste bloco.
  bool failed = false;

  bool has(String key) => values.containsKey(key);

  T? get<T>(String key) => values[key] as T?;

  int lineOf(String key) => lines[key] ?? blockLine;
}

/// Problema num caminho de arquivo do curso, ou `null` se estiver bem.
/// [existing] são os arquivos da pasta; [extensions] vazio aceita qualquer.
String? coursePathProblem(
  String path,
  Set<String> existing, {
  List<String> extensions = const [],
}) {
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('//') ||
      path.startsWith('data:')) {
    return '`$path` é de fora da pasta do curso; coloque o arquivo em '
        '`media/` e use o caminho relativo.';
  }
  if (path.startsWith('/') ||
      path.contains(r'\') ||
      _schemePattern.hasMatch(path) ||
      path.split('/').contains('..')) {
    return 'o caminho `$path` sai da pasta do curso; use um caminho '
        'relativo como `media/arquivo.png` (sem `..` nem `/` no começo).';
  }
  final dot = path.lastIndexOf('.');
  final extension = dot < 0 ? '' : path.substring(dot).toLowerCase();
  if (extensions.isNotEmpty && !extensions.contains(extension)) {
    return '`$path` não tem um formato aceito aqui '
        '(${extensions.join(', ')}).';
  }
  if (!existing.contains(path)) {
    return 'o arquivo `$path` não existe na pasta do curso.';
  }
  return null;
}

/// A mensagem do pacote `yaml` (em inglês) em português, para os erros mais
/// comuns de quem escreve à mão; o resto vai com o texto original.
String yamlProblem(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('flow sequence')) {
    return 'uma lista entre colchetes `[ ]` está sem fechar ou sem vírgula '
        'entre os itens ($message)';
  }
  if (lower.contains('flow mapping')) {
    return 'um mapa entre chaves `{ }` está sem fechar ou sem vírgula entre '
        'os itens ($message)';
  }
  if (lower.contains('mapping values are not allowed')) {
    return 'dois-pontos no lugar errado; se o valor tem `:`, ponha-o entre '
        'aspas ($message)';
  }
  if (lower.contains('duplicate mapping key')) {
    return 'a mesma chave aparece duas vezes ($message)';
  }
  if (lower.contains('tab')) {
    return 'o YAML não aceita tabulação; indente com espaços ($message)';
  }
  if (lower.contains('quote') || lower.contains('unterminated')) {
    return 'aspas sem fechar ($message)';
  }
  return message;
}

/// Lê blocos YAML contra o vocabulário e junta os erros no [issues].
class FieldReader {
  FieldReader(this.issues, this.existing);

  final FileIssues issues;

  /// Arquivos da pasta do curso, para conferir `file:` e `image:`.
  final Set<String> existing;

  /// O YAML de [yaml] como mapa, ou `null` (com o erro já registrado).
  /// [firstLine] é a linha do arquivo em que a linha 0 do YAML está.
  YamlMap? parseMap(String yaml, int firstLine, {required int blockLine}) {
    final YamlNode node;
    try {
      node = loadYamlNode(yaml);
    } on YamlException catch (e) {
      final line = firstLine + (e.span?.start.line ?? 0);
      issues.error(line, 'YAML inválido: ${yamlProblem(e.message)}');
      return null;
    }
    if (node is YamlMap) return node;
    if (node is YamlScalar && node.value == null) {
      return YamlMap();
    }
    issues.error(
      firstLine + node.span.start.line,
      'O corpo precisa ser uma lista de `chave: valor`.',
    );
    return null;
  }

  /// Confere as chaves de [map] contra [defs] e lê os valores.
  /// [where] entra nas mensagens ("na marca `zywny-score`").
  Fields read(
    YamlMap map,
    Map<String, KeyDef> defs, {
    required int firstLine,
    required int blockLine,
    required String where,
  }) {
    final fields = Fields(blockLine);
    int lineOf(YamlNode node) => firstLine + node.span.start.line;

    for (final entry in map.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final valueNode = entry.value;
      final keyLine = lineOf(keyNode);
      final key = keyNode.value;
      if (key is! String) {
        issues.error(keyLine, 'A chave `$key` não é um texto $where.');
        fields.failed = true;
        continue;
      }
      final def = defs[key];
      if (def == null) {
        final hint = suggestFor(key, defs.keys);
        issues.error(
          keyLine,
          hint != null
              ? 'chave desconhecida `$key` — você quis dizer `$hint`?'
              : 'chave desconhecida `$key` (chaves aceitas $where: '
                    '${defs.keys.join(', ')}).',
        );
        fields.failed = true;
        continue;
      }
      fields.lines[key] = keyLine;
      final value = _readValue(
        key,
        def,
        valueNode,
        fields,
        lineOf(valueNode),
        firstLine,
        blockLine,
      );
      if (value == null) {
        fields.failed = true;
      } else {
        fields.values[key] = value;
      }
    }

    for (final entry in defs.entries) {
      if (entry.value.required && !map.containsKey(entry.key)) {
        issues.error(
          blockLine,
          'falta a chave obrigatória `${entry.key}` $where.',
        );
        fields.failed = true;
      }
    }
    return fields;
  }

  Object? _readValue(
    String key,
    KeyDef def,
    YamlNode node,
    Fields fields,
    int line,
    int firstLine,
    int blockLine,
  ) {
    final value = node.value;

    Object? bad(String message) {
      issues.error(line, message);
      return null;
    }

    switch (def.type) {
      case ValueType.text:
        if (value is String && value.trim().isNotEmpty) return value;
        return bad('`$key` precisa ser um texto não vazio.');
      case ValueType.scalarText:
        if (value is String && value.trim().isNotEmpty) return value;
        if (value is num || value is bool) return '$value';
        return bad('`$key` precisa ser um texto ou um número.');
      case ValueType.id:
        if (value is String && _idPattern.hasMatch(value)) return value;
        return bad(
          '`$key` inválido: use de 1 a 40 letras minúsculas, números ou '
          'hífens${value is String ? ' (recebi `$value`)' : ''}.',
        );
      case ValueType.integer:
        if (value is! int) {
          return bad('`$key` precisa ser um número inteiro.');
        }
        if ((def.min != null && value < def.min!) ||
            (def.max != null && value > def.max!)) {
          return bad(
            '`$key` precisa estar entre ${def.min} e ${def.max} '
            '(recebi $value).',
          );
        }
        return value;
      case ValueType.boolean:
        if (value is bool) return value;
        return bad(
          '`$key` precisa ser `true` ou `false` (`yes` e `no` não valem).',
        );
      case ValueType.option:
        return _option(key, value, def.values, bad);
      case ValueType.note:
        if (value is String) {
          return Pitch.tryParse(value) ?? bad(Pitch.invalidMessage(value));
        }
        return bad('`$key` precisa ser uma nota, como C4.');
      case ValueType.noteList:
        return _list(key, node, def, fields, firstLine, bad, (item, itemLine) {
          final v = item.value;
          if (v is String) {
            final pitch = Pitch.tryParse(v);
            if (pitch != null) return pitch;
            issues.error(itemLine, Pitch.invalidMessage(v));
            return null;
          }
          issues.error(itemLine, 'esperava uma nota, como C4.');
          return null;
        });
      case ValueType.notes:
        if (node is YamlMap) {
          return read(
            node,
            kRandomNotesKeys,
            firstLine: firstLine,
            blockLine: line,
            where: 'em `notes`',
          );
        }
        if (node is YamlList) {
          if (node.isEmpty) {
            return bad('`notes` não pode ser uma lista vazia.');
          }
          return _list(key, node, def, fields, firstLine, bad, (item, l) {
            final v = item.value;
            if (v is String) {
              final pitch = Pitch.tryParse(v);
              if (pitch != null) return pitch;
              issues.error(l, Pitch.invalidMessage(v));
              return null;
            }
            issues.error(l, 'esperava uma nota, como C4.');
            return null;
          });
        }
        return bad(
          '`notes` precisa ser uma lista (`[C4, E4, G4]`) ou um sorteio '
          '(`{random: C4-G5, count: 12}`).',
        );
      case ValueType.letterList:
        return _list(key, node, def, fields, firstLine, bad, (item, l) {
          final v = item.value;
          if (v is String && RegExp(r'^[A-G]$').hasMatch(v)) return v;
          issues.error(l, 'esperava uma letra de A a G (recebi `$v`).');
          return null;
        }, unique: true);
      case ValueType.figureList:
        final wires = Figure.values.map((f) => f.wire).toList();
        return _list(key, node, def, fields, firstLine, bad, (item, l) {
          final v = item.value;
          final figure = v is String
              ? Figure.values.where((f) => f.wire == v).firstOrNull
              : null;
          if (figure != null) return figure;
          final hint = v is String ? suggestSimilar(v, wires) : null;
          issues.error(
            l,
            'figura desconhecida `$v`'
            '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
            '(figuras: ${wires.join(', ')}).',
          );
          return null;
        }, unique: true);
      case ValueType.stringList:
        return _list(key, node, def, fields, firstLine, bad, (item, l) {
          final v = item.value;
          if (v is String && v.trim().isNotEmpty) return v;
          if (v is num || v is bool) return '$v';
          issues.error(l, 'esperava um texto.');
          return null;
        });
      case ValueType.path:
        if (value is! String || value.trim().isEmpty) {
          return bad('`$key` precisa ser o caminho de um arquivo da pasta.');
        }
        final problem = coursePathProblem(
          value,
          existing,
          extensions: def.extensions,
        );
        if (problem != null) return bad(problem);
        return value;
      case ValueType.link:
        if (value is String &&
            value.startsWith('https://') &&
            value.length > 8 &&
            !value.contains(RegExp(r'\s'))) {
          return value;
        }
        return bad('`$key` precisa ser um endereço `https://…`.');
      case ValueType.keyName:
        if (value is String && kKeyNames.contains(value)) return value;
        return bad(
          '`$key` não é um tom que o formato conhece${value is String ? ' '
                    '(`$value`)' : ''}; use ${kKeyNames.take(15).join(', ')} ou '
          'o menor com `m` (Am, Em…).',
        );
      case ValueType.timeSignature:
        if (value is String && kTimeSignatures.contains(value)) return value;
        return bad(
          '`$key` aceita ${kTimeSignatures.join(', ')}'
          '${value != null ? ' (recebi `$value`)' : ''}.',
        );
      case ValueType.measureRange:
        final text = '$value';
        final match = value is String || value is int
            ? _measurePattern.firstMatch(text)
            : null;
        if (match != null) {
          final from = int.parse(match.group(1)!);
          final to = int.parse(match.group(2) ?? match.group(1)!);
          if (from >= 1 && to >= from) return MeasureRange(from, to);
        }
        return bad(
          '`$key` precisa ser um compasso (`5`) ou uma faixa crescente '
          '(`"5-12"`), contando do 1.',
        );
      case ValueType.abc:
        if (value is String && value.trim().isNotEmpty) {
          final problem = abcProblem(value);
          return problem == null ? value : bad(problem);
        }
        return bad(
          '`$key` precisa ser o texto ABC (use `|` para várias '
          'linhas).',
        );
      case ValueType.passMap:
        if (node is! YamlMap) {
          return bad('`pass` precisa ser um mapa, como `{accuracy: 90}`.');
        }
        return read(
          node,
          {for (final e in kPassKeys.entries) e.key: e.value.def},
          firstLine: firstLine,
          blockLine: line,
          where: 'em `pass`',
        );
    }
  }

  String? _option(
    String key,
    Object? value,
    List<String> values,
    Object? Function(String) bad,
  ) {
    if (value is String && values.contains(value)) return value;
    final hint = value is String ? suggestFor(value, values) : null;
    bad(
      '`$key` aceita ${values.join(', ')}'
      '${value != null ? '; recebi `$value`' : ''}'
      '${hint != null ? ' — você quis dizer `$hint`?' : '.'}',
    );
    return null;
  }

  /// Lê uma lista item a item; devolve `null` se algum item falhou.
  List<Object>? _list(
    String key,
    YamlNode node,
    KeyDef def,
    Fields fields,
    int firstLine,
    Object? Function(String) bad,
    Object? Function(YamlNode item, int line) parseItem, {
    bool unique = false,
  }) {
    if (node is! YamlList) {
      bad('`$key` precisa ser uma lista, como `[a, b]`.');
      return null;
    }
    if (node.length < def.minItems) {
      bad(
        '`$key` precisa de pelo menos ${def.minItems} '
        '${def.minItems == 1 ? 'item' : 'itens'}.',
      );
      return null;
    }
    final result = <Object>[];
    final lines = <int>[];
    var ok = true;
    for (final item in node.nodes) {
      final itemLine = firstLine + item.span.start.line;
      final parsed = parseItem(item, itemLine);
      if (parsed == null) {
        ok = false;
        continue;
      }
      if (unique && result.contains(parsed)) {
        issues.error(itemLine, '`$key` repete `$parsed`.');
        ok = false;
        continue;
      }
      result.add(parsed);
      lines.add(itemLine);
    }
    fields.itemLines[key] = lines;
    return ok ? result : null;
  }
}

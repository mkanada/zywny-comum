import 'package:yaml/yaml.dart';

import 'abc_limits.dart';
import 'course_issue.dart';
import 'course_model.dart';

import 'package:zywny_music/note_name.dart';

import 'suggest.dart';
import 'vocabulary.dart';

final _idPattern = RegExp(kIdPattern);
final _measurePattern = RegExp(r'^(\d+)(?:-(\d+))?$');
final _intRangePattern = RegExp(r'^(\d+)-(\d+)$');
final _letterPattern = RegExp(r'^[A-G]$');
final _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');

/// Os valores já lidos de um bloco YAML (front matter, marca ou sub-mapa),
/// com a linha de cada chave para os erros seguintes.
class Fields {
  Fields(this.blockLine, this.firstLine);

  /// Linha da abertura do bloco; vale para o que não tem linha própria.
  final int blockLine;

  /// Linha do arquivo em que a linha 0 do YAML do bloco está.
  final int firstLine;
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

/// Onde fica um bloco YAML: a linha do arquivo em que o YAML começa, a abertura
/// do bloco (para o que não tem linha própria) e o nome do bloco nas mensagens.
class FieldBlock {
  const FieldBlock({
    required this.firstLine,
    required this.blockLine,
    required this.where,
  });

  /// Linha do arquivo em que a linha 0 do YAML está.
  final int firstLine;

  /// Linha da abertura do bloco.
  final int blockLine;

  /// Como o bloco se chama nas mensagens ("na marca `zywny-score`").
  final String where;
}

/// Um valor de campo a ser lido: a chave, a definição, o nó YAML e os campos
/// do bloco em que ele está.
class _ValueRead {
  _ValueRead(this.key, this.def, this.node, this.fields);

  final String key;
  final KeyDef def;
  final YamlNode node;
  final Fields fields;

  Object? get value => node.value;

  /// Linha do valor no arquivo.
  int get line => fields.firstLine + node.span.start.line;
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

  /// Confere as chaves de [map] contra [defs] e lê os valores; [at] diz onde
  /// o bloco está e como se chama nas mensagens.
  Fields read(YamlMap map, Map<String, KeyDef> defs, FieldBlock at) {
    final fields = Fields(at.blockLine, at.firstLine);
    for (final entry in map.nodes.entries) {
      _readEntry(entry, defs, fields, at);
    }
    _checkRequired(map, defs, fields, at);
    return fields;
  }

  void _readEntry(
    MapEntry<dynamic, YamlNode> entry,
    Map<String, KeyDef> defs,
    Fields fields,
    FieldBlock at,
  ) {
    final keyNode = entry.key as YamlNode;
    final keyLine = at.firstLine + keyNode.span.start.line;
    final key = keyNode.value;
    if (key is! String) {
      issues.error(keyLine, 'A chave `$key` não é um texto ${at.where}.');
      fields.failed = true;
      return;
    }
    final def = defs[key];
    if (def == null) {
      final hint = suggestFor(key, defs.keys);
      issues.error(
        keyLine,
        hint != null
            ? 'chave desconhecida `$key` — você quis dizer `$hint`?'
            : 'chave desconhecida `$key` (chaves aceitas ${at.where}: '
                  '${defs.keys.join(', ')}).',
      );
      fields.failed = true;
      return;
    }
    fields.lines[key] = keyLine;
    final value = _readValue(_ValueRead(key, def, entry.value, fields));
    if (value == null) {
      fields.failed = true;
    } else {
      fields.values[key] = value;
    }
  }

  void _checkRequired(
    YamlMap map,
    Map<String, KeyDef> defs,
    Fields fields,
    FieldBlock at,
  ) {
    for (final entry in defs.entries) {
      if (entry.value.required && !map.containsKey(entry.key)) {
        issues.error(
          at.blockLine,
          'falta a chave obrigatória `${entry.key}` ${at.where}.',
        );
        fields.failed = true;
      }
    }
  }

  /// Lê um valor pelo tipo dele. `null` se não é válido: o erro já foi
  /// registrado.
  Object? _readValue(_ValueRead v) {
    final reader = _readers[v.def.type];
    if (reader == null) throw StateError('sem leitor para ${v.def.type}');
    return reader(v);
  }

  /// Um leitor por tipo de valor: cada um lê o nó do campo e registra o erro
  /// na linha do valor.
  late final Map<ValueType, Object? Function(_ValueRead)> _readers = {
    ValueType.text: _readText,
    ValueType.scalarText: _readScalarText,
    ValueType.id: _readId,
    ValueType.integer: _readInteger,
    ValueType.boolean: _readBoolean,
    ValueType.option: _readOption,
    ValueType.note: _readNote,
    ValueType.noteList: _readNoteList,
    ValueType.notes: _readNotes,
    ValueType.letterList: _readLetterList,
    ValueType.figureList: _readFigureList,
    ValueType.stringList: _readStringList,
    ValueType.path: _readPath,
    ValueType.link: _readLink,
    ValueType.keyName: _readKeyName,
    ValueType.keyChoice: _readKeyChoice,
    ValueType.timeSignature: _readTimeSignature,
    ValueType.measureRange: _readMeasureRange,
    ValueType.intRange: _readIntRange,
    ValueType.abc: _readAbc,
    ValueType.chordsSpec: _readChordsSpec,
    ValueType.optionOrList: _readOptionOrList,
    ValueType.chartSpec: _readChartSpec,
    ValueType.patternSpec: _readPatternSpec,
    ValueType.backingSpec: _readBackingSpec,
    ValueType.echoSource: _readEchoSource,
    ValueType.melodySpec: _readMelodySpec,
    ValueType.enterSpec: _readEnterSpec,
    ValueType.tempoLadder: _readTempoLadder,
    ValueType.passMap: _readPassMap,
  };

  // --- Texto e identificadores ---------------------------------------------

  Object? _readText(_ValueRead v) {
    final value = v.value;
    if (value is String && value.trim().isNotEmpty) return value;
    return _bad(v, '`${v.key}` precisa ser um texto não vazio.');
  }

  Object? _readScalarText(_ValueRead v) {
    final value = v.value;
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num || value is bool) return '$value';
    return _bad(v, '`${v.key}` precisa ser um texto ou um número.');
  }

  Object? _readId(_ValueRead v) {
    final value = v.value;
    if (value is String && _idPattern.hasMatch(value)) return value;
    return _bad(
      v,
      '`${v.key}` inválido: use de 1 a 40 letras minúsculas, números ou '
      'hífens${value is String ? ' (recebi `$value`)' : ''}.',
    );
  }

  Object? _readLink(_ValueRead v) {
    final value = v.value;
    if (value is String &&
        value.startsWith('https://') &&
        value.length > 8 &&
        !value.contains(RegExp(r'\s'))) {
      return value;
    }
    return _bad(v, '`${v.key}` precisa ser um endereço `https://…`.');
  }

  Object? _readAbc(_ValueRead v) {
    final value = v.value;
    if (value is String && value.trim().isNotEmpty) {
      final problem = abcProblem(value);
      return problem == null ? value : _bad(v, problem);
    }
    return _bad(
      v,
      '`${v.key}` precisa ser o texto ABC (use `|` para várias linhas).',
    );
  }

  Object? _readPath(_ValueRead v) {
    final value = v.value;
    if (value is! String || value.trim().isEmpty) {
      return _bad(
        v,
        '`${v.key}` precisa ser o caminho de um arquivo da pasta.',
      );
    }
    final problem = coursePathProblem(
      value,
      existing,
      extensions: v.def.extensions,
    );
    if (problem != null) return _bad(v, problem);
    return value;
  }

  // --- Números, notas, tons e compassos ------------------------------------

  Object? _readInteger(_ValueRead v) {
    final value = v.value;
    final def = v.def;
    if (value is! int) {
      return _bad(v, '`${v.key}` precisa ser um número inteiro.');
    }
    if ((def.min != null && value < def.min!) ||
        (def.max != null && value > def.max!)) {
      return _bad(
        v,
        '`${v.key}` precisa estar entre ${def.min} e ${def.max} '
        '(recebi $value).',
      );
    }
    return value;
  }

  Object? _readBoolean(_ValueRead v) {
    final value = v.value;
    if (value is bool) return value;
    return _bad(
      v,
      '`${v.key}` precisa ser `true` ou `false` (`yes` e `no` não valem).',
    );
  }

  Object? _readNote(_ValueRead v) {
    final value = v.value;
    if (value is String) {
      return Pitch.tryParse(value) ?? _bad(v, Pitch.invalidMessage(value));
    }
    return _bad(v, '`${v.key}` precisa ser uma nota, como C4.');
  }

  Object? _readKeyName(_ValueRead v) {
    final value = v.value;
    if (value is String && kKeyNames.contains(value)) return value;
    return _bad(v, _keyMessage(v.key, value));
  }

  Object? _readTimeSignature(_ValueRead v) {
    final value = v.value;
    if (value is String && kTimeSignatures.contains(value)) return value;
    return _bad(
      v,
      '`${v.key}` aceita ${kTimeSignatures.join(', ')}'
      '${value != null ? ' (recebi `$value`)' : ''}.',
    );
  }

  Object? _readMeasureRange(_ValueRead v) {
    final value = v.value;
    final match = value is String || value is int
        ? _measurePattern.firstMatch('$value')
        : null;
    if (match != null) {
      final from = int.parse(match.group(1)!);
      final to = int.parse(match.group(2) ?? match.group(1)!);
      if (from >= 1 && to >= from) return MeasureRange(from, to);
    }
    return _bad(
      v,
      '`${v.key}` precisa ser um compasso (`5`) ou uma faixa crescente '
      '(`"5-12"`), contando do 1.',
    );
  }

  Object? _readIntRange(_ValueRead v) {
    final value = v.value;
    final def = v.def;
    final match = value is String ? _intRangePattern.firstMatch(value) : null;
    if (match != null) {
      final from = int.parse(match.group(1)!);
      final to = int.parse(match.group(2)!);
      final low = def.min ?? from, high = def.max ?? to;
      if (from >= low && to <= high && to >= from) return (from, to);
    }
    return _bad(
      v,
      '`${v.key}` precisa ser uma faixa crescente entre ${def.min} e '
      '${def.max}, como `"60-70"`.',
    );
  }

  // --- Opções ----------------------------------------------------------------

  Object? _readOption(_ValueRead v) => _optionIn(v, v.def.values);

  Object? _readKeyChoice(_ValueRead v) {
    // EX05: `all` e `random` são palavras; a lista traz tons, com a mesma
    // validação do `key:`.
    if (v.node is! YamlList) return _optionIn(v, const ['all', 'random']);
    return _list(v, (item, line) => _keyItem(v, item, line), unique: true);
  }

  Object? _readOptionOrList(_ValueRead v) {
    if (v.node is! YamlList) return _optionIn(v, v.def.values);
    return _list(v, (item, line) => _optionItem(v, item, line), unique: true);
  }

  // --- Listas ----------------------------------------------------------------

  Object? _readNoteList(_ValueRead v) => _list(v, _noteItem);

  Object? _readLetterList(_ValueRead v) => _list(v, _letterItem, unique: true);

  Object? _readFigureList(_ValueRead v) => _list(v, _figureItem, unique: true);

  Object? _readStringList(_ValueRead v) => _list(v, _stringItem);

  // --- Mapas e blocos com forma própria --------------------------------------

  Object? _readNotes(_ValueRead v) {
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kRandomNotesKeys, 'em `notes`');
    }
    if (node is YamlList) {
      if (node.isEmpty) return _bad(v, '`notes` não pode ser uma lista vazia.');
      return _list(v, _noteItem);
    }
    return _bad(
      v,
      '`notes` precisa ser uma lista (`[C4, E4, G4]`) ou um sorteio '
      '(`{random: C4-G5, count: 12}`).',
    );
  }

  Object? _readChordsSpec(_ValueRead v) {
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kChordRandomKeys, 'em `chords`');
    }
    if (node is YamlList) return _list(v, _chordItem);
    return _bad(
      v,
      '`chords` precisa ser uma lista de cifras (`[C, Am7, F/A]`) ou um '
      'sorteio (`{qualities: [M, m], count: 10}`).',
    );
  }

  Object? _readChartSpec(_ValueRead v) {
    // EX11: a grade escrita (texto) ou o mapa da biblioteca.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kChartMapKeys, 'em `chart`');
    }
    final value = v.value;
    if (value is String && value.trim().isNotEmpty) return value;
    return _bad(
      v,
      '`chart` precisa ser a grade escrita (texto) ou um mapa como '
      '`{progression: I-IV-V-I, key: C}`.',
    );
  }

  Object? _readPatternSpec(_ValueRead v) {
    // EX11: o nome de um padrão da biblioteca, ou o molde escrito.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kPatternMapKeys, 'em `pattern`');
    }
    final value = v.value;
    if (value is String && value.trim().isNotEmpty) return value;
    return _bad(
      v,
      '`pattern` precisa ser o nome de um padrão (como `oom-pah`) ou um '
      'mapa como `{grid: 8, left: "1 5 6 5 1 5 6 5", right: ". . C . . . C ."}`.',
    );
  }

  Object? _readBackingSpec(_ValueRead v) {
    // EX12: o texto `drums` (só a bateria) ou o mapa da base.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kBackingMapKeys, 'em `backing`');
    }
    if (v.value == 'drums') return v.value;
    return _bad(
      v,
      '`backing` precisa ser `drums` (só a bateria) ou um mapa como '
      '`{style: shuffle, bass: walking}`.',
    );
  }

  Object? _readEchoSource(_ValueRead v) {
    // EX14: o mapa da fonte (escala, acordes ou licks).
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kEchoSourceKeys, 'em `source`');
    }
    return _bad(
      v,
      '`source` precisa ser um mapa como `{scale: major, key: C, '
      'range: C4-G5}`, `{chord-tones: true}` ou `{licks: blues-basic}`.',
    );
  }

  Object? _readMelodySpec(_ValueRead v) {
    // EX16: o mapa da melodia, `{step, key}` ou `{file}`.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kMelodyMapKeys, 'em `melody`');
    }
    return _bad(
      v,
      '`melody` precisa ser um mapa como `{step: 7b, key: G}` ou '
      '`{file: media/folclore.musicxml}`.',
    );
  }

  Object? _readEnterSpec(_ValueRead v) {
    // EX20: o mapa de entrada do `follow-form`, `{bars, pattern}` ou
    // `{section, pattern}`.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kFollowEnterKeys, 'em `enter`');
    }
    return _bad(
      v,
      '`enter` precisa ser um mapa como `{bars: 11-12, pattern: block}` ou '
      '`{section: B, pattern: block}`.',
    );
  }

  Object? _readTempoLadder(_ValueRead v) {
    // EX22: o mapa `{from, to, step, back}`, com as quatro chaves.
    final node = v.node;
    if (node is YamlMap) {
      return _readSub(v, node, kTempoLadderKeys, 'em `tempo-ladder`');
    }
    return _bad(
      v,
      '`tempo-ladder` precisa ser um mapa, como '
      '`{from: 60, to: 96, step: 4, back: 8}`.',
    );
  }

  Object? _readPassMap(_ValueRead v) {
    final node = v.node;
    if (node is! YamlMap) {
      return _bad(v, '`pass` precisa ser um mapa, como `{accuracy: 90}`.');
    }
    return _readSub(v, node, {
      for (final e in kPassKeys.entries) e.key: e.value.def,
    }, 'em `pass`');
  }

  /// Lê um sub-mapa de [v] contra [keys]; [where] entra nas mensagens dele.
  Fields _readSub(
    _ValueRead v,
    YamlMap map,
    Map<String, KeyDef> keys,
    String where,
  ) {
    return read(
      map,
      keys,
      FieldBlock(
        firstLine: v.fields.firstLine,
        blockLine: v.line,
        where: where,
      ),
    );
  }

  // --- Itens e erros ---------------------------------------------------------

  /// Um item de nota (`C4`), o mesmo nas listas e no sorteio de `notes`.
  Object? _noteItem(YamlNode item, int line) {
    final value = item.value;
    if (value is String) {
      final pitch = Pitch.tryParse(value);
      if (pitch != null) return pitch;
      issues.error(line, Pitch.invalidMessage(value));
      return null;
    }
    issues.error(line, 'esperava uma nota, como C4.');
    return null;
  }

  Object? _letterItem(YamlNode item, int line) {
    final value = item.value;
    if (value is String && _letterPattern.hasMatch(value)) return value;
    issues.error(line, 'esperava uma letra de A a G (recebi `$value`).');
    return null;
  }

  Object? _figureItem(YamlNode item, int line) {
    final value = item.value;
    final wires = Figure.values.map((f) => f.wire).toList();
    final figure = value is String
        ? Figure.values.where((f) => f.wire == value).firstOrNull
        : null;
    if (figure != null) return figure;
    final hint = value is String ? suggestSimilar(value, wires) : null;
    issues.error(
      line,
      'figura desconhecida `$value`'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''} '
      '(figuras: ${wires.join(', ')}).',
    );
    return null;
  }

  Object? _stringItem(YamlNode item, int line) {
    final value = item.value;
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num || value is bool) return '$value';
    issues.error(line, 'esperava um texto.');
    return null;
  }

  Object? _chordItem(YamlNode item, int line) {
    final value = item.value;
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num) return '$value';
    issues.error(line, 'esperava uma cifra, como `Am7` ou `C/E`.');
    return null;
  }

  Object? _keyItem(_ValueRead v, YamlNode item, int line) {
    final value = item.value;
    if (value is String && kKeyNames.contains(value)) return value;
    issues.error(line, _keyMessage(v.key, value));
    return null;
  }

  Object? _optionItem(_ValueRead v, YamlNode item, int line) {
    final value = item.value;
    final values = v.def.values;
    if (value is String && values.contains(value)) return value;
    final hint = value is String ? suggestFor(value, values) : null;
    issues.error(
      line,
      '`${v.key}` aceita ${values.join(', ')}'
      '${hint != null ? ' — você quis dizer `$hint`?' : ''}.',
    );
    return null;
  }

  /// A mensagem de um tom que o formato não conhece; [value] é o que foi escrito.
  String _keyMessage(String key, Object? value) =>
      '`$key` não é um tom que o formato conhece'
      '${value is String ? ' (`$value`)' : ''}; use '
      '${kKeyNames.take(15).join(', ')} ou o menor com `m` (Am, Em…).';

  /// Uma opção de [values] escrita como texto (ou número, em `grouping: 4`).
  /// Erro se não é uma delas.
  String? _optionIn(_ValueRead v, List<String> values) {
    final value = v.value;
    if (value is String && values.contains(value)) return value;
    // `grouping: 4` e `order: 132` são números no YAML; a palavra é o texto.
    if (value is int && values.contains('$value')) return '$value';
    final hint = value is String ? suggestFor(value, values) : null;
    _bad(
      v,
      '`${v.key}` aceita ${values.join(', ')}'
      '${value != null ? '; recebi `$value`' : ''}'
      '${hint != null ? ' — você quis dizer `$hint`?' : '.'}',
    );
    return null;
  }

  /// Lê uma lista item a item com [parseItem]; devolve `null` se algum item
  /// falhou. [unique] recusa item repetido.
  List<Object>? _list(
    _ValueRead v,
    Object? Function(YamlNode item, int line) parseItem, {
    bool unique = false,
  }) {
    final node = v.node;
    final key = v.key;
    final def = v.def;
    if (node is! YamlList) {
      _bad(v, '`$key` precisa ser uma lista, como `[a, b]`.');
      return null;
    }
    if (node.length < def.minItems) {
      _bad(
        v,
        '`$key` precisa de pelo menos ${def.minItems} '
        '${def.minItems == 1 ? 'item' : 'itens'}.',
      );
      return null;
    }
    final result = <Object>[];
    final lines = <int>[];
    var ok = true;
    for (final item in node.nodes) {
      final itemLine = v.fields.firstLine + item.span.start.line;
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
    v.fields.itemLines[key] = lines;
    return ok ? result : null;
  }

  /// Registra o erro na linha do valor e devolve `null` (o valor não serve).
  Object? _bad(_ValueRead v, String message) {
    issues.error(v.line, message);
    return null;
  }
}

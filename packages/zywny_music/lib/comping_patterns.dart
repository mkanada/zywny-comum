import 'package:meta/meta.dart';

// EX11 — a biblioteca de moldes do `play-chart`: cada padrão rítmico é um
// molde por mão, com um símbolo por parte do compasso. Dart puro: o validador
// do curso lê os nomes e a sintaxe sem Flutter, e o app gera os ataques.
//
// Os moldes são nossos. A ideia de cada um vem da descrição do livro (PFA,
// Pike, Neely, Rawlins, Harrison, Valerio), não o texto dele.

/// O que um símbolo do molde pede do aluno.
enum CompingKind {
  /// `.`: nada, ou segura o que vinha.
  rest,

  /// `C`: o acorde inteiro.
  chord,

  /// Um grau (`1`, `b7`, `10`…), ou `B`, que é o mesmo que `1`.
  degree,

  /// Dois graus juntos (`1+5`): a fundamental e a 5ª num só ataque.
  dyad,

  /// `T`: qualquer nota do acorde.
  tone,

  /// `X`: qualquer nota (só o ritmo).
  any,

  /// `A`: a nota que leva à fundamental do acorde seguinte (a regra 3 do
  /// `walking-bass`, de Rawlins).
  approach,
}

/// Um símbolo lido de um molde: o tipo e, quando há, os graus (já
/// normalizados: `10` vira `3`, uma oitava acima). O `B` sai como `1`.
@immutable
class CompingSymbol {
  const CompingSymbol(this.kind, [this.degrees = const []]);

  final CompingKind kind;

  /// Os graus, com `degree` (um) ou `dyad` (dois). Vazio nos outros.
  final List<String> degrees;

  bool get isAttack => kind != CompingKind.rest;

  @override
  bool operator ==(Object other) =>
      other is CompingSymbol &&
      other.kind == kind &&
      _sameDegrees(other.degrees, degrees);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(degrees));

  @override
  String toString() => switch (kind) {
    CompingKind.degree => degrees.first,
    CompingKind.dyad => degrees.join('+'),
    _ => kind.name,
  };

  static bool _sameDegrees(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final _degreePattern = RegExp(r'^([b#]?)(1[0-3]|[1-9])$');

/// O grau sem a oitava: `10` é a 3ª, `11` a 4ª, `12` a 5ª, `13` a 6ª. Os
/// acidentes ficam na frente (`b7`, `#3`).
String compingDegreeOf(String text) {
  final match = _degreePattern.firstMatch(text);
  if (match == null) {
    throw ArgumentError.value(text, 'text', 'não é um grau do molde');
  }
  final number = int.parse(match.group(2)!);
  final octaveDown = number > 9 ? number - 7 : number;
  return '${match.group(1)}$octaveDown';
}

/// O símbolo de [text] (um token do molde), ou `null` se não é um símbolo.
CompingSymbol? compingSymbolOf(String text) {
  switch (text) {
    case '.':
      return const CompingSymbol(CompingKind.rest);
    case 'C':
      return const CompingSymbol(CompingKind.chord);
    case 'B':
      return const CompingSymbol(CompingKind.degree, ['1']);
    case 'T':
      return const CompingSymbol(CompingKind.tone);
    case 'X':
      return const CompingSymbol(CompingKind.any);
    case 'A':
      return const CompingSymbol(CompingKind.approach);
  }
  final parts = text.split('+');
  if (parts.length > 2 || parts.any((p) => !_degreePattern.hasMatch(p))) {
    return null;
  }
  final degrees = [for (final p in parts) compingDegreeOf(p)];
  return degrees.length == 1
      ? CompingSymbol(CompingKind.degree, degrees)
      : CompingSymbol(CompingKind.dyad, degrees);
}

/// Lê uma linha de molde (`"1 . 5 ."`) com [grid] símbolos por compasso. Um
/// `|` separa os compassos de um molde de dois ou mais. Devolve `null` e
/// chama [error] com a mensagem do primeiro problema (símbolo desconhecido,
/// ou número de símbolos diferente de [grid]).
List<List<CompingSymbol>>? parseCompingLine(
  String line, {
  required int grid,
  void Function(String message)? error,
}) {
  final bars = <List<CompingSymbol>>[];
  for (final bar in line.split('|')) {
    final tokens = bar.trim().split(RegExp(r'\s+'));
    final symbols = <CompingSymbol>[];
    for (final token in tokens) {
      final symbol = compingSymbolOf(token);
      if (symbol == null) {
        error?.call('`$token` não é um símbolo do molde');
        return null;
      }
      symbols.add(symbol);
    }
    if (symbols.length != grid) {
      error?.call(
        'um compasso do molde tem ${symbols.length} símbolos, e `grid` pede '
        '$grid',
      );
      return null;
    }
    bars.add(symbols);
  }
  return bars;
}

/// Um padrão de comping: o compasso, o `grid` (partes iguais por compasso) e
/// o molde de cada mão, como texto (`"B . . ."`, com `|` entre compassos).
/// [time] é `null` no molde escrito no exercício, que vale em qualquer
/// compasso; os da biblioteca são de 4/4 salvo quando dizem outro.
@immutable
class CompingPattern {
  const CompingPattern({
    required this.name,
    required this.grid,
    required this.left,
    required this.right,
    this.time = '4/4',
    this.swingDefault = false,
    this.idea = '',
    this.source = '',
  });

  final String name;
  final String? time;
  final int grid;

  /// O molde da mão esquerda e o da direita; `.` nas duas quando a mão não toca.
  final String left;
  final String right;

  /// `true` quando o padrão nasce com swing (no `swing` de quem não escreve um).
  final bool swingDefault;

  /// A ideia de cada mão, como na tabela da especificação.
  final String idea;

  /// Onde o padrão vem (o livro e o capítulo).
  final String source;

  /// Os compassos do molde: 1, ou 2 no montuno e na bossa.
  int get bars => '|'.allMatches(left).length + 1;

  /// Os símbolos da mão esquerda, por compasso.
  List<List<CompingSymbol>> get leftBars => _linesOf(left);

  /// Os símbolos da mão direita, por compasso.
  List<List<CompingSymbol>> get rightBars => _linesOf(right);

  List<List<CompingSymbol>> _linesOf(String line) =>
      parseCompingLine(line, grid: grid) ??
      (throw StateError('o molde `$name` não lê: `$line`'));

  @override
  String toString() => 'CompingPattern($name)';
}

/// `pattern: any` (EX11): vale qualquer ritmo. Só o acorde e o baixo nos
/// tempos 1 e 3 são cobrados; o resto do que o aluno tocar é extra. O gerador
/// põe os ataques pelo tempo (não pelo `grid`), então o `grid` aqui é só o da
/// desenho do molde.
const kAnyCompingPattern = CompingPattern(
  name: 'any',
  grid: 4,
  left: 'B . B .',
  right: 'C . C .',
  time: null,
  idea: 'qualquer ritmo: só o acorde e o baixo nos tempos 1 e 3 são cobrados',
);

/// O padrão de nome [name], ou `null`.
CompingPattern? compingPatternNamed(String name) {
  for (final pattern in kCompingPatterns) {
    if (pattern.name == name) return pattern;
  }
  return null;
}

/// Os nomes dos padrões, na ordem da tabela (para o erro com sugestão).
List<String> get compingPatternNames => [
  for (final pattern in kCompingPatterns) pattern.name,
];

/// A biblioteca do `pattern:` (EX11). Um padrão por linha da tabela da
/// especificação; a ordem é a dos grupos (PFA, Hal Leonard, jazz, latino).
const kCompingPatterns = <CompingPattern>[
  // PFA, livro 1: os 14 ritmos de mão direita e esquerda.
  CompingPattern(
    name: 'block',
    grid: 4,
    left: 'B . . .',
    right: 'C . . .',
    idea: 'acorde na direita no tempo 1, baixo na esquerda no 1',
    source: 'Pike 7',
  ),
  CompingPattern(
    name: 'left-note-right-chord',
    grid: 4,
    left: 'B . . .',
    right: '. C C C',
    idea: 'baixo no 1 e acorde no 2, 3 e 4',
    source: 'PFA 1, ritmo 1',
  ),
  CompingPattern(
    name: 'straight-beat',
    grid: 4,
    left: 'B . B .',
    right: 'C C C C',
    idea: 'acorde em cada tempo na direita, baixo no 1 e no 3',
    source: 'PFA 1, ritmo 2',
  ),
  CompingPattern(
    name: 'half-beat-bounce',
    grid: 8,
    left: 'B . . . B . . .',
    right: 'C C C C C C C C',
    idea: 'acorde em colcheias na direita, com o baixo no 1 e no 3',
    source: 'PFA 1, ritmo 3',
  ),
  CompingPattern(
    name: 'oom-pah',
    grid: 4,
    left: 'B . 5 .',
    right: '. C . C',
    idea: 'baixo no 1, acorde no 2, a 5ª no 3, acorde no 4',
    source: 'PFA 1, ritmo 4; Pearl 10',
  ),
  CompingPattern(
    name: 'oom-pah-pah',
    time: '3/4',
    grid: 3,
    left: 'B . .',
    right: '. C C',
    idea: 'baixo no 1, acorde no 2 e no 3 (valsa)',
    source: 'PFA 1, ritmo 5; Pearl 10',
  ),
  CompingPattern(
    name: 'six-eight-split',
    time: '6/8',
    grid: 6,
    left: '1 . 5 . 8 .',
    right: '. 3 . 5 . .',
    idea: 'arpejo 1-5-8 na esquerda e 3-5 na direita',
    source: 'PFA 1, ritmo 6',
  ),
  CompingPattern(
    name: 'split-chord',
    grid: 4,
    left: 'B . 5 .',
    right: '. 3 . 8',
    idea:
        'acorde dividido entre as mãos: a fundamental e a 5ª na esquerda, a '
        '3ª e a 8ª na direita',
    source: 'PFA 1, ritmo 7',
  ),
  CompingPattern(
    // Tercinas em 4/4 (grade 12): a grade de 12/8 não é um `time:` do curso.
    name: 'country-shuffle',
    grid: 12,
    left: 'B . . 5 . . B . . 5 . .',
    right: '. . C . . C . . C . . C',
    idea: 'baixo alternado 1-5 e acorde nas tercinas de trás',
    source: 'PFA 1, ritmo 8; Harrison Country 4',
  ),
  CompingPattern(
    name: 'twist',
    grid: 8,
    left: 'B B 5 5 B B 5 5',
    right: '. . C . . . C .',
    idea: 'baixo em colcheias 1-1-5-5 e acorde no 2 e no 4',
    source: 'PFA 1, ritmos 9 e 13',
  ),
  CompingPattern(
    name: 'static-broken',
    grid: 8,
    left: 'B 5 8 5 B 5 8 5',
    right: 'T . . . . . . .',
    idea: 'acorde quebrado 1-5-8-5 na esquerda e nota longa na direita',
    source: 'PFA 1, ritmo 10; Pearl 11',
  ),
  CompingPattern(
    name: 'three-beat-bounce',
    time: '3/4',
    grid: 6,
    left: 'B . . . . .',
    right: '. C C . C .',
    idea: 'baixo no 1 e acorde no "e" do 1, no 2 e no 3',
    source: 'PFA 1, ritmo 11',
  ),
  CompingPattern(
    name: 'bossa-bounce',
    grid: 8,
    left: 'B . . 5 . . B .',
    right: '. C . . C . . C',
    idea: 'baixo 1-5 em semínimas pontuadas e o acorde sincopado da bossa',
    source: 'PFA 1, ritmo 12; Valerio Latin 5',
  ),
  CompingPattern(
    name: 'reggae',
    grid: 8,
    left: 'B . . . . . . .',
    right: '. C . C . C . C',
    idea: 'acorde só nos contratempos, e baixo no 1',
    source: 'PFA 1, ritmo 14',
  ),
  // Hal Leonard (cap. 4 de cada estilo) e os blues.
  CompingPattern(
    name: 'rock-eighths',
    grid: 8,
    left: 'B B B B B B B B',
    right: 'C . C . C . C .',
    idea: 'baixo em colcheias na esquerda e acorde em semínimas',
    source: 'Harrison Beginning Rock 2',
  ),
  CompingPattern(
    name: 'boogie',
    grid: 8,
    left: '1 5 6 5 1 5 6 5',
    right: '. . C . . . C .',
    swingDefault: true,
    idea: '1-5-6-5 em colcheias na esquerda e o acorde no 2 e no 4',
    source: 'PFA 2; Harrison Blues 3',
  ),
  CompingPattern(
    name: 'boogie-walking',
    grid: 8,
    left: '1 3 5 6 b7 6 5 3',
    right: '. . . . . . . .',
    swingDefault: true,
    idea: '1-3-5-6-b7-6-5-3 na esquerda',
    source: 'Harrison Blues 3; Vinter',
  ),
  CompingPattern(
    name: 'stride',
    grid: 4,
    left: 'B C B C',
    right: '. . . .',
    idea: 'baixo no 1 e no 3 (grave), acorde no 2 e no 4 (médio)',
    source: 'Valerio Stride 4; PFA 8 (fake stride)',
  ),
  CompingPattern(
    name: 'charleston',
    grid: 8,
    left: '7 . 3 . 7 . 3 .',
    right: 'C . . C . . . .',
    swingDefault: true,
    idea: 'acorde no 1 e no "e" do 2 (sete-três na esquerda)',
    source: 'Harrison Intro 2',
  ),
  CompingPattern(
    name: 'jazz-in-2',
    grid: 8,
    left: 'B . . . B . . .',
    right: '. . . C . . C .',
    swingDefault: true,
    idea: 'baixo no 1 e no 3 e acorde no "e" do 2 e no 4',
    source: 'Harrison Intro 3',
  ),
  // Latino.
  CompingPattern(
    name: 'montuno',
    grid: 8,
    left: 'B . . . . . . B | B . . . . . . B',
    right: 'C . C . . C . C | . C . C . C . .',
    idea:
        'o montuno de 2 compassos em oitavas na direita e o tumbao na '
        'esquerda (antecipa o 4)',
    source: 'Martignon 4; Valerio Latin 1',
  ),
  // Ballad e fake book.
  CompingPattern(
    name: 'ballad-arpeggio',
    grid: 8,
    left: '1 5 8 10 1 5 8 10',
    right: 'C . . . . . . .',
    idea:
        'arpejo aberto 1-5-8-10 na esquerda em colcheias e acorde ou melodia '
        'na direita',
    source: 'PFA 6; Harrison Smooth Jazz 4',
  ),
  CompingPattern(
    name: 'fake-root',
    grid: 4,
    left: 'B . . .',
    right: '. . . .',
    idea: 'só a fundamental na esquerda no tempo 1 (1º degrau do Fake Book)',
    source: 'Neely Fake Book 1',
  ),
  CompingPattern(
    name: 'fake-fifth',
    grid: 4,
    left: '1+5 . . .',
    right: '. . . .',
    idea: 'fundamental + 5ª juntas na esquerda no tempo 1 (2º degrau)',
    source: 'Neely Fake Book 1',
  ),
  CompingPattern(
    name: 'fake-two-part',
    grid: 4,
    left: 'B T T T',
    right: '. . . .',
    idea:
        'fundamental no 1 e as outras notas do acorde no 2, 3 e 4 na '
        'esquerda (opção 1 de ME)',
    source: 'Neely Fake Book 4',
  ),
  CompingPattern(
    name: 'bass-in-two',
    grid: 4,
    left: 'B . 5 .',
    right: '. . . .',
    idea:
        'linha de baixo em mínimas (fundamental no 1 e 5ª no 3, ou invertido '
        'para não repetir a nota através da barra), com acordes opcionais na '
        'direita',
    source: 'Neely Fake Book 4; Rawlins Real Book 5',
  ),
  // Rawlins, cap. 5: as linhas de baixo andantes.
  CompingPattern(
    name: 'walking-two',
    grid: 4,
    left: '1 1 5 5',
    right: '. . . .',
    idea: 'o baixo em dois com cada nota repetida em semínimas (1-1-5-5)',
    source: 'Rawlins Real Book 5',
  ),
  CompingPattern(
    name: 'walking-1235',
    grid: 4,
    left: '1 2 3 5',
    right: 'C . . .',
    idea:
        'linha andante pelo molde ascendente 1 2 3 5 (ou 1 2 3 #3 quando o '
        'próximo acorde está uma 4ª acima), e acordes na direita',
    source: 'Rawlins Real Book 5',
  ),
  CompingPattern(
    name: 'walking-8765',
    grid: 4,
    left: '8 7 6 5',
    right: 'C . . .',
    idea: 'linha andante pelo molde descendente 8 7 6 5, e acordes na direita',
    source: 'Rawlins Real Book 5',
  ),
  CompingPattern(
    name: 'walking-bass',
    grid: 4,
    left: '1 X T A',
    right: '. . . .',
    idea:
        'linha livre na esquerda, avaliada pelas 3 regras de Rawlins; com ou '
        'sem comping na direita',
    source: 'Rawlins Real Book 5',
  ),
  CompingPattern(
    name: 'bossa-bass',
    grid: 8,
    left: '1 . . . 5 . . .',
    right: '. . C . . C . .',
    idea:
        'baixo de bossa em dois (1 e 5, com síncope) na esquerda e acordes '
        'sincopados na direita',
    source: 'Rawlins Real Book 5',
  ),
  CompingPattern(
    name: 'rumba-bass',
    grid: 8,
    left: '1 . . 5 . . 8 .',
    right: '. . . . . . . .',
    idea: 'duas semínimas pontuadas e uma semínima (3+3+2 colcheias)',
    source: 'Rawlins Real Book 5',
  ),
];

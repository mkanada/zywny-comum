import 'package:meta/meta.dart';

// EX13 — a biblioteca dos grooves do `rhythm` com duas mãos: cada groove tem um
// molde por mão, com um símbolo por parte do compasso (`X` ataque, `A` ataque
// acentuado, `-` segura a nota anterior, `.` pausa de uma parte, `|` entre
// compassos). Dart puro: o validador do curso lê os nomes e a sintaxe sem
// Flutter.
//
// Os moldes são nossos. A ideia de cada um vem da descrição do livro (Pearl,
// Martignon, Willey, Valerio, Cowling, Harrison), não o texto dele. Os da clave
// de rumba, da bossa e do samba são para confirmar por ouvido.

/// Unidades por semínima. Uma figura tem um número inteiro delas: a 16ª tem 3,
/// a 8ª tem 6, a semínima tem 12 e o compasso de 4/4 tem 48.
const kRhythmUnitsPerQuarter = 12;

/// As unidades de um compasso do ritmo, ou `null` se não é um deles.
int? _unitsOfBar(String time) => switch (time) {
  '4/4' => 48,
  '3/4' => 36,
  '2/4' => 24,
  '6/8' => 36,
  _ => null,
};

/// Quantas unidades tem o compasso [time]: 4/4 tem 48, 3/4 e 6/8 têm 36, 2/4
/// tem 24. Lança [ArgumentError] para outro compasso.
int rhythmBarUnits(String time) {
  final units = _unitsOfBar(time);
  if (units == null) {
    throw ArgumentError.value(
      time,
      'time',
      'não é um compasso do ritmo (use 4/4, 3/4, 2/4 ou 6/8)',
    );
  }
  return units;
}

/// As durações (em unidades) que têm figura escrita: a 16ª, a 8ª e a 4ª com
/// ponto e de tercina, e as maiores (a tercina de semibreve é 32, a semibreve
/// com ponto é 72).
const _notatableUnits = {2, 3, 4, 6, 8, 9, 12, 16, 18, 24, 32, 36, 48, 72};

/// `true` se uma figura de [units] tem nome escrito (sem ligadura).
bool rhythmNotatable(int units) => _notatableUnits.contains(units);

/// Um símbolo do molde do ritmo. Cada símbolo é uma parte do compasso (a grade
/// do molde); um ataque e os `-` que vêm depois dele são uma só nota.
enum RhythmSymbol {
  /// `.`: uma parte de silêncio.
  rest,

  /// `X`: ataque (uma nota que começa aqui).
  attack,

  /// `A`: ataque acentuado (o medidor `accents`, EX07).
  accent,

  /// `-`: segura a nota do ataque anterior por mais uma parte. Não vale no
  /// começo do compasso nem depois de uma pausa.
  hold,
}

RhythmSymbol? _symbolOf(String token) => switch (token) {
  '.' => RhythmSymbol.rest,
  'X' => RhythmSymbol.attack,
  'A' => RhythmSymbol.accent,
  '-' => RhythmSymbol.hold,
  _ => null,
};

/// Lê um molde de ritmo (`"X - . X | A . . -"`): um símbolo por parte do
/// compasso, e `|` entre os compassos, que têm todos o mesmo número de
/// símbolos. Devolve `null` e chama [error] com a mensagem do primeiro problema.
///
/// Um `-` sem ataque antes dele no mesmo compasso (no começo do compasso ou
/// depois de uma pausa) é erro: não há ligadura entre compassos.
///
/// Com [time], confere também a grade (o número de símbolos tem de dividir o
/// compasso em partes iguais) e as figuras. Um evento é um ataque com os `-`
/// que vêm depois, ou uma sequência de pausas; a duração de cada evento tem de
/// se escrever (ver [rhythmNotatable]), senão é erro. Sem [time], só a sintaxe.
List<List<RhythmSymbol>>? parseRhythmMolde(
  String line, {
  String? time,
  void Function(String message)? error,
}) {
  final units = time == null ? null : _unitsOfBar(time);
  if (time != null && units == null) {
    error?.call('o compasso `$time` não é do ritmo (use 4/4, 3/4, 2/4 ou 6/8)');
    return null;
  }
  final bars = <List<RhythmSymbol>>[];
  for (final bar in line.split('|')) {
    final text = bar.trim();
    if (text.isEmpty) {
      error?.call('há um compasso vazio no molde');
      return null;
    }
    final symbols = <RhythmSymbol>[];
    for (final token in text.split(RegExp(r'\s+'))) {
      final symbol = _symbolOf(token);
      if (symbol == null) {
        error?.call(
          '`$token` não é um símbolo do ritmo (use `X`, `A`, `-` ou `.`)',
        );
        return null;
      }
      if (symbol == RhythmSymbol.hold &&
          (symbols.isEmpty || symbols.last == RhythmSymbol.rest)) {
        error?.call('`-` segura uma nota: falta um ataque antes dele');
        return null;
      }
      symbols.add(symbol);
    }
    if (bars.isNotEmpty && symbols.length != bars.first.length) {
      error?.call(
        'o compasso ${bars.length + 1} tem ${symbols.length} símbolos, e o '
        'primeiro tem ${bars.first.length}',
      );
      return null;
    }
    bars.add(symbols);
  }
  if (units == null) return bars;

  final count = bars.first.length;
  if (units % count != 0) {
    error?.call(
      '$count símbolos por compasso não dividem $units unidades em partes '
      'iguais',
    );
    return null;
  }
  final step = units ~/ count;
  for (var b = 0; b < bars.length; b++) {
    final bar = bars[b];
    var start = 0; // o símbolo que abre o evento atual
    var slots = 0; // quantas partes ele dura (0: nenhum evento aberto)
    var resting = false; // se o evento atual são pausas
    for (var i = 0; i <= count; i++) {
      final symbol = i < count ? bar[i] : null;
      final continues =
          symbol == RhythmSymbol.hold ||
          (symbol == RhythmSymbol.rest && resting);
      if (continues) {
        slots++;
        continue;
      }
      // Fecha o evento que vinha e abre o do símbolo atual (se há um).
      final length = slots * step;
      if (slots > 0 && !rhythmNotatable(length)) {
        error?.call(
          'no compasso ${b + 1}, a figura do símbolo ${start + 1} dura '
          '$length unidades (uma semínima tem $kRhythmUnitsPerQuarter), e essa '
          'duração não se escreve: ponha um ataque onde ela se divide',
        );
        return null;
      }
      start = i;
      slots = symbol == null ? 0 : 1;
      resting = symbol == RhythmSymbol.rest;
    }
  }
  return bars;
}

/// Um groove do `rhythm` com duas mãos (EX13): o compasso, quantas mãos tocam,
/// o molde de cada uma (como texto, com `|` entre os compassos) e de onde vem
/// a ideia. A mão esquerda é `null` quando ela não toca (`hands: 1`).
@immutable
class RhythmGroove {
  const RhythmGroove({
    required this.name,
    required this.time,
    required this.hands,
    required this.right,
    this.left,
    this.idea = '',
    this.source = '',
  }) : assert(
         hands == (left == null ? 1 : 2),
         'hands é 1 sem a mão esquerda, e 2 com ela',
       );

  final String name;

  /// O compasso do ritmo: `4/4`, `3/4`, `2/4` ou `6/8`.
  final String time;

  /// Quantas mãos tocam: 1 (só a direita) ou 2.
  final int hands;

  /// O molde da mão direita, e o da esquerda (`null` quando ela não toca).
  final String right;
  final String? left;

  /// A ideia do groove, como na tabela da especificação.
  final String idea;

  /// Onde o groove vem (o livro e o capítulo).
  final String source;

  /// Os compassos do molde da direita: 1, ou 2 no son e na clave.
  List<List<RhythmSymbol>> get rightBars => _barsOf(right, 'direita');

  /// Os compassos do molde da esquerda; vazio quando ela não toca.
  List<List<RhythmSymbol>> get leftBars {
    final molde = left;
    return molde == null ? const [] : _barsOf(molde, 'esquerda');
  }

  /// Quantos compassos o molde ocupa (1 ou 2, o mesmo nas duas mãos).
  int get bars => rightBars.length;

  List<List<RhythmSymbol>> _barsOf(String line, String hand) {
    String? problem;
    final bars = parseRhythmMolde(
      line,
      time: time,
      error: (message) {
        problem ??= message;
      },
    );
    return bars ??
        (throw StateError('o groove `$name` ($hand) não lê: $problem'));
  }

  @override
  String toString() => 'RhythmGroove($name)';
}

/// A tabela dos grooves do `rhythm` com duas mãos (EX13), na ordem do plano.
const kRhythmGrooves = <RhythmGroove>[
  // Pearl 16: 2 contra 3 e 3 contra 2, o pulso de tercinas contra colcheias.
  RhythmGroove(
    name: 'two-against-three',
    time: '4/4',
    hands: 2,
    right: 'X X X X X X X X X X X X',
    left: 'X X X X X X X X',
    idea: 'tercinas na direita (3 por tempo) contra colcheias na esquerda (2)',
    source: 'Pearl 16',
  ),
  RhythmGroove(
    name: 'three-against-two',
    time: '4/4',
    hands: 2,
    right: 'X X X X X X X X',
    left: 'X X X X X X X X X X X X',
    idea: 'colcheias na direita (2 por tempo) contra tercinas na esquerda (3)',
    source: 'Pearl 16',
  ),
  // Martignon 4: a clave contra o tumbao (o "e" do 2 e o 4 na esquerda).
  RhythmGroove(
    name: 'clave-son-3-2',
    time: '4/4',
    hands: 2,
    right: 'X . . X . . X . | . . X . X . . .',
    left: '. . . X . . X . | . . . X . . X .',
    idea: 'clave de son 3-2 em colcheias na direita, tumbao na esquerda',
    source: 'Martignon 4',
  ),
  RhythmGroove(
    name: 'clave-son-2-3',
    time: '4/4',
    hands: 2,
    right: '. . X . X . . . | X . . X . . X .',
    left: '. . . X . . X . | . . . X . . X .',
    idea: 'clave de son 2-3 em colcheias na direita, tumbao na esquerda',
    source: 'Martignon 4',
  ),
  RhythmGroove(
    name: 'clave-rumba-3-2',
    time: '4/4',
    hands: 2,
    right: 'X . . X . . . X | . . X . . X . .',
    left: '. . . X . . X . | . . . X . . X .',
    idea:
        'clave de rumba 3-2 na direita (o último 3 no "e" do 4), tumbao na '
        'esquerda; para confirmar por ouvido',
    source: 'Martignon 4',
  ),
  // Valerio, Latin 5: a clave de bossa e a fundamental da bossa na esquerda.
  RhythmGroove(
    name: 'bossa-clave',
    time: '4/4',
    hands: 2,
    right: 'X . . X . . X . | . . X . . X . .',
    left: 'X - - X X - - X | X - - X X - - X',
    idea:
        'clave brasileira 3:2 na direita; a fundamental na semínima pontuada (X '
        '- -) e na colcheia (X) da esquerda; para confirmar por ouvido',
    source: 'Valerio Latin 5',
  ),
  // Willey 2 e 4: as linhas do tamborim e o surdo.
  RhythmGroove(
    name: 'samba-surdo',
    time: '4/4',
    hands: 2,
    right: 'X . X X . X X .',
    left: '. . X - - - - -',
    idea:
        'linha de tamborim em colcheias na direita, surdo longo (mínima com '
        'ponto, X - - - - -) a partir do 2 na esquerda; para confirmar por ouvido',
    source: 'Willey 2 e 4',
  ),
  // Willey 4: o pulso de semicolcheias do ganzá, uma mão só.
  RhythmGroove(
    name: 'ganza',
    time: '4/4',
    hands: 1,
    right: 'X X X A X X X A X X X A X X X A',
    idea: 'semicolcheias do ganzá, com acento na 4ª semicolcheia de cada tempo',
    source: 'Willey 4',
  ),
  // Cowling 7: o contratempo do "palmas" no 2 e no 4.
  RhythmGroove(
    name: 'backbeat',
    time: '4/4',
    hands: 2,
    right: '. . X . . . X .',
    left: 'X . . . X . . .',
    idea: 'palmas no 2 e no 4 na direita, 1 e 3 na esquerda',
    source: 'Cowling 7',
  ),
  // Harrison, Intro 2: o 1 e o "e" do 2 na direita; o baixo em semínimas.
  RhythmGroove(
    name: 'charleston',
    time: '4/4',
    hands: 2,
    right: 'X . . X . . X .',
    left: 'X . X . X . X .',
    idea:
        'o 1, o "e" do 2 e o 4 na direita; o baixo em semínimas, 1, 2, 3 e 4, '
        'na esquerda',
    source: 'Harrison Intro 2',
  ),
];

/// O groove de [name], ou `null`.
RhythmGroove? rhythmGrooveNamed(String name) {
  for (final groove in kRhythmGrooves) {
    if (groove.name == name) return groove;
  }
  return null;
}

/// Os nomes dos grooves, na ordem da tabela (para o erro com sugestão).
List<String> get rhythmGrooveNames => [
  for (final groove in kRhythmGrooves) groove.name,
];

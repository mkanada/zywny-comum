// EX12 — os estilos da base gerada: um molde de bateria (notas GM) e um molde
// de baixo por estilo. Dados puros, sem Flutter: o validador do curso lê os
// nomes, e o gerador (no zywny-aprendizado) monta as notas a partir deles.
//
// Os moldes são nossos, escritos a partir da ideia de cada estilo (EX12).
// Confira o groove com o usuário no aceite, por ouvido.

import 'comping_patterns.dart';

/// Um golpe da bateria GM: a nota e a velocity-base (a humanização soma ±6).
class DrumHit {
  const DrumHit(this.note, this.velocity);

  final int note;
  final int velocity;
}

/// As letras do molde de bateria. `+` junta peças no mesmo tempo (`k+h`).
const kDrumPieces = <String, DrumHit>{
  'k': DrumHit(36, 96), // bumbo
  's': DrumHit(38, 92), // caixa, no acento
  'g': DrumHit(38, 40), // caixa fantasma
  'h': DrumHit(42, 70), // chimbal fechado
  'o': DrumHit(46, 80), // chimbal aberto
  'p': DrumHit(44, 60), // chimbal com o pé
  'r': DrumHit(51, 78), // prato de condução
  'c': DrumHit(37, 80), // aro
  'l': DrumHit(75, 90), // claves
  'm': DrumHit(70, 75), // chocalho (ganzá)
  'w': DrumHit(56, 85), // cowbell
  'z': DrumHit(39, 88), // palmas
  'x': DrumHit(49, 100), // prato de ataque (a última nota da forma)
};

/// Um estilo da base. O molde de bateria tem `grid` tempos por compasso e
/// `bars` compassos (`|` separa os compassos na escrita). O molde de baixo usa
/// a mesma grade, com os graus do molde de comping (`1`, `5`, `b7`…); `bass`
/// é `null` quando o estilo não tem baixo de molde (quem faz é o gerador).
class BackingStyle {
  const BackingStyle({
    required this.name,
    required this.time,
    required this.grid,
    required this.bars,
    required this.drums,
    required this.bass,
    required this.source,
  });

  final String name;

  /// A fórmula de compasso: `4/4`, `3/4` ou `6/8`.
  final String time;

  /// Os tempos de cada compasso na grade do molde.
  final int grid;

  /// Quantos compassos o molde ocupa (1 ou 2).
  final int bars;

  /// O molde de bateria, `grid × bars` tokens.
  final String drums;

  /// O molde de baixo, `grid × bars` tokens, ou `null`.
  final String? bass;

  /// De onde vem a ideia (o livro e a página).
  final String source;
}

/// Os estilos da base, na ordem da tabela do EX12.
const kBackingStyles = <BackingStyle>[
  BackingStyle(
    name: 'straight',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k+h h s+h h k+h h s+h h',
    bass: '1 . 5 . 1 . 5 .',
    source: 'Harrison Beginning Rock 2',
  ),
  BackingStyle(
    name: 'rock',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k+h k s+h h k+h k s+h h',
    bass: '1 1 1 1 1 1 1 1',
    source: 'Miller; Harrison',
  ),
  BackingStyle(
    name: 'shuffle',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k+h g s+h h k+h g s+h h',
    bass: '1 . 3 . 5 . 6 .',
    source: 'Harrison Blues; PFA 2',
  ),
  BackingStyle(
    name: 'swing',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'r+k . r+p . r g r+p .',
    bass: '1 . 3 . 5 . 6 .',
    source: 'Harrison Intro; Valerio',
  ),
  BackingStyle(
    name: 'two-beat',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k . s . k . s .',
    bass: '1 . . . 5 . . .',
    source: 'Harrison Country 4',
  ),
  BackingStyle(
    name: 'waltz',
    time: '3/4',
    grid: 6,
    bars: 1,
    drums: 'k . h . h .',
    bass: '1 . . . . .',
    source: 'PFA 1, oom-pah-pah',
  ),
  BackingStyle(
    name: 'six-eight',
    time: '6/8',
    grid: 6,
    bars: 1,
    drums: 'k+h h h k+h h h',
    bass: '1 . . 5 . .',
    source: 'PFA 1, six-eight-split',
  ),
  BackingStyle(
    name: 'ballad',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'h h c+h h h h c+h h',
    bass: '1 . . . . . . .',
    source: 'Harrison Smooth Jazz; PFA 6',
  ),
  BackingStyle(
    name: 'bossa',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k+h h c+h k h c h h',
    bass: '1 . . 5 . . 1 .',
    source: 'Valerio Latin 5; Willey 5',
  ),
  BackingStyle(
    name: 'samba',
    time: '4/4',
    grid: 16,
    bars: 1,
    drums: 'm m m m k+m m m m m m m m k+m m m m',
    bass: '1 . . . 1 . . . 1 . . . 1 . . .',
    source: 'Willey 2 e 4',
  ),
  BackingStyle(
    name: 'salsa-3-2',
    time: '4/4',
    grid: 8,
    bars: 2,
    drums: 'l+w . w l w . l+w . | w . l+w . l+w . w .',
    bass: '1 . . 1 . . 5 . | 1 . . 1 . . 5 .',
    source: 'Martignon 4; Valerio Latin 1',
  ),
  BackingStyle(
    name: 'salsa-2-3',
    time: '4/4',
    grid: 8,
    bars: 2,
    drums: 'w . l+w . l+w . w . | l+w . w l w . l+w .',
    bass: '1 . . 1 . . 5 . | 1 . . 1 . . 5 .',
    source: 'Martignon 4; Valerio Latin 1',
  ),
  BackingStyle(
    name: 'reggae',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: '. h . h k+c h . h',
    bass: '1 . . 1 . . . .',
    source: 'PFA 1, ritmo 14',
  ),
  BackingStyle(
    name: 'gospel-shuffle',
    time: '4/4',
    grid: 8,
    bars: 1,
    drums: 'k+h g s+z+h h k+h g s+z+h h',
    bass: '1 . 3 . 5 . 6 .',
    source: 'Cowling 8',
  ),
  BackingStyle(
    name: 'funk',
    time: '4/4',
    grid: 16,
    bars: 1,
    drums: 'k+h h g+h h s+h h g+h h k+h h g+h h s+h h g+h k+h',
    bass: '1 . . 1 . . 1 . . . 1 . 1 . . .',
    source: 'Harrison R&B 4',
  ),
];

/// Os nomes dos estilos, na ordem da tabela (para o validador).
final List<String> backingStyleNames = [
  for (final style in kBackingStyles) style.name,
];

/// O estilo de [name], ou `null` se não há.
BackingStyle? backingStyleNamed(String name) {
  for (final style in kBackingStyles) {
    if (style.name == name) return style;
  }
  return null;
}

/// O estilo que o `backing:` usa quando não diz `style:`: o que combina com o
/// molde de comping (o feel, o compasso e o gênero dos nomes da biblioteca).
BackingStyle backingStyleFor(CompingPattern pattern) {
  final name = pattern.name;
  final style = switch (name) {
    _ when pattern.time == '3/4' => 'waltz',
    _ when pattern.time == '6/8' => 'six-eight',
    _ when name.startsWith('boogie') || name == 'country-shuffle' => 'shuffle',
    _ when pattern.swingDefault => 'swing',
    'bossa-bounce' || 'bossa-bass' => 'bossa',
    'montuno' => 'salsa-2-3',
    'rumba-bass' => 'salsa-3-2',
    'reggae' => 'reggae',
    'ballad-arpeggio' || 'fake-root' || 'fake-fifth' => 'ballad',
    'fake-two-part' || 'bass-in-two' => 'ballad',
    'rock-eighths' || 'twist' => 'rock',
    _ => 'straight',
  };
  return backingStyleNamed(style)!;
}

/// Um molde de bateria lido: um tempo por lista de golpes (vazia é pausa).
/// `null` se o molde não cabe em `grid × bars` ou tem uma peça desconhecida.
List<List<DrumHit>>? parseDrumLine(String line, {required int slots}) {
  final tokens = line
      .split(RegExp(r'[\s|]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length != slots) return null;
  final out = <List<DrumHit>>[];
  for (final token in tokens) {
    if (token == '.') {
      out.add(const []);
      continue;
    }
    final hits = <DrumHit>[];
    for (final piece in token.split('+')) {
      final hit = kDrumPieces[piece];
      if (hit == null) return null;
      hits.add(hit);
    }
    out.add(hits);
  }
  return out;
}

/// O molde de baixo de [style] como símbolos, um por tempo da grade; `null` se
/// o estilo não tem baixo de molde.
List<CompingSymbol>? bassSymbolsOf(BackingStyle style) {
  final bass = style.bass;
  if (bass == null) return null;
  final bars = parseCompingLine(bass, grid: style.grid);
  if (bars == null) return null;
  return [for (final bar in bars) ...bar];
}

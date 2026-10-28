import 'chord_degree.dart';
import 'scale.dart';

// EX06 — o dedilhado das escalas e dos arpejos do `play-pattern`.
//
// Só entra o que o livro traz: Pike, *How to Play Piano*, "Escalas maiores",
// "Escalas menores harmônicas selecionadas" e "Arpejos de duas oitavas"
// (exemplos 121 a 127 do apêndice). O padrão é por família de tônica: o texto do
// livro diz que o dedilhado de Ré vale também para Dó e Sol. Tônica fora da
// família, outra qualidade de acorde e mão esquerda em mais de uma oitava não
// têm dedilhado: o `pattern_score` não escreve nada nesses casos (o plano manda
// assim, e as notas registram a lacuna).
//
// O número de cada nota é o dedo na subida, contado da tônica. Na descida, a
// nota fica com o dedo que tinha na subida: o livro escreve assim no dó maior
// (F4 com 1 e E4 com 3 nas duas direções).

/// Tônicas da família do dó maior: a mão direita de Dó e Ré (Pike, exemplo
/// 121) vale para elas. Sol, Lá, Mi e Si seguem o mesmo padrão; só Dó e Sol
/// foram conferidos no livro.
const _majorFamily = {'C', 'G', 'D', 'A', 'E', 'B'};

/// Escala menor harmônica: Lá e Ré (Pike, exemplos 124 e 125).
const _harmonicMinorFamily = {'A', 'D'};

/// Mão direita, uma oitava (8 notas, da tônica à tônica): 1 2 3 1 2 3 4 5.
const _rightOctave = [1, 2, 3, 1, 2, 3, 4, 5];

/// Cada oitava depois da primeira (as 7 notas que faltam, sem a tônica do
/// topo, que já veio com o 5): 1 2 3 1 2 3 4.
const _rightNextOctave = [1, 2, 3, 1, 2, 3, 4];

/// Mão esquerda, uma oitava (do dó grave ao agudo): 5 4 3 2 1 3 2 1.
const _leftOctave = [5, 4, 3, 2, 1, 3, 2, 1];

/// Arpejo de tríade, mão direita: 1 2 3 em cada oitava e o 5 no topo (Pike,
/// exemplo 126: 1 2 3 1 2 3 5).
const _rightArpeggioOctave = [1, 2, 3];

/// Arpejo de tríade, mão esquerda, uma oitava: 5 3 2 1.
const _leftArpeggio = [5, 3, 2, 1];

/// O dedo de cada nota de uma escala de [kind] que sobe [octaves] oitavas
/// (da tônica até a oitava acima, inclusive: 8 notas em uma oitava e 15 em duas),
/// na mão direita ([right]) ou na esquerda. `null` quando não há dedilhado
/// para esse caso.
///
/// Só a escala maior e a menor harmônica têm tabela, nas tônicas das famílias
/// acima. A mão esquerda só tem a primeira oitava.
List<int>? scaleFingering(
  ScaleKind kind,
  KeySpec key, {
  required bool right,
  required int octaves,
}) {
  final tonic = key.spelling;
  final inFamily =
      (kind == ScaleKind.major && _majorFamily.contains(tonic)) ||
      (kind == ScaleKind.harmonicMinor && _harmonicMinorFamily.contains(tonic));
  if (!inFamily) return null;
  if (!right) return octaves == 1 ? _leftOctave : null;
  return [
    ..._rightOctave,
    for (var n = 1; n < octaves; n++) ..._rightNextOctave,
  ];
}

/// O dedilhado de um arpejo de tríade de [octaves] oitavas, na mão direita ou
/// na esquerda. O mesmo serve à tríade maior e à menor (a 3ª muda de altura,
/// não de dedo; Pike só traz o maior, então o menor é o mesmo padrão, não
/// conferido no livro). O arpejo tem uma nota a mais que as oitavas (o topo).
/// `null` sem tabela: tônica fora da família, ou mão esquerda em mais de uma
/// oitava.
List<int>? arpeggioFingering(
  KeySpec key, {
  required bool right,
  required int octaves,
}) {
  if (!_majorFamily.contains(key.spelling)) return null;
  if (!right) return octaves == 1 ? _leftArpeggio : null;
  return [for (var n = 0; n < octaves; n++) ..._rightArpeggioOctave, 5];
}

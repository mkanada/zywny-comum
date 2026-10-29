// As pautas da banda (T15): a bateria, o baixo, a harmonia e o contracanto que
// tocam junto com o aluno nos primeiros níveis. Não têm partitura; quem as põe
// na trilha é `PerformanceTrack.withBand`. Sem Flutter: a linha de comando
// (`hand.dart`) também as lê.

/// A primeira pauta da banda: tudo que vem depois da 2 (a mão esquerda) é da
/// banda.
const kBandFirstStaff = 3;

/// As pautas da banda: bateria (3), baixo (4), harmonia (5) e contracanto (6).
const kBandStaves = {3, 4, 5, 6};

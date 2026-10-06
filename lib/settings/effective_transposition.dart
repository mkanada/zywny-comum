import '../library/piece.dart';
import '../music/transposition.dart';
import 'app_settings.dart';
import 'piece_settings.dart';

/// A nota mais grave e a mais aguda do catálogo de hinos, em MIDI (Q01: 27 a
/// 86). Com elas nenhuma direção da tabela do Q00 sai de A0–C8, então quem
/// ainda não renderizou a música pode usá-las para escolher a direção.
const int kCatalogLowestMidi = 27;
const int kCatalogHighestMidi = 86;

/// A transposição com que [piece] abre, ou `null` para abrir no tom original.
/// É o único lugar que decide isso (fase Q, docs/plano/Q03):
///
///  1. a escolha da música ([PieceSettings.transpose]) vale sempre: um
///     intervalo transpõe, [kTransposeNone] ("Não") vence a chave geral;
///  2. sem escolha, a chave geral ([AppSettings.transposeByDefault]) leva a
///     armadura da música ([Piece.fifths]) para sem acidentes — e não age
///     numa música sem armadura conhecida, nem numa que já não a tem.
///
/// [lowest] e [highest] são a nota mais grave e a mais aguda da música
/// **original**, em MIDI, para escolher a direção quando uma não cabe no
/// teclado. Quem já renderizou a música passa o que leu do `midi.json`; a
/// primeira vez usa a faixa do catálogo de hinos.
Transposition? effectiveTransposition(
  Piece piece,
  PieceSettings pieceSettings,
  AppSettings appSettings, {
  int lowest = kCatalogLowestMidi,
  int highest = kCatalogHighestMidi,
}) {
  final chosen = pieceSettings.transpose;
  if (chosen != null) {
    return chosen == kTransposeNone ? null : Transposition.parse(chosen);
  }
  final fifths = piece.fifths;
  if (!appSettings.transposeByDefault || fifths == null) return null;
  return Transposition.toNoAccidentals(
    fifths,
    lowest: lowest,
    highest: highest,
  );
}

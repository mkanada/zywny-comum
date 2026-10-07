import 'package:meta/meta.dart';

import 'note_names.dart' show NoteNaming, kFlatSign, kSharpSign;
import 'transposition.dart';

/// Os textos da tela de "Transpor" (fase Q, docs/plano/Q08): a armadura em
/// poucos caracteres, a lista dos 12 tons e o selo da partitura. Só conta — a
/// tela guarda e desenha.

/// A armadura em poucos caracteres: "3♭", "2♯", "0".
String keySignatureShort(int fifths) => switch (fifths) {
  0 => '0',
  > 0 => '$fifths$kSharpSign',
  _ => '${-fifths}$kFlatSign',
};

/// "3♭ → 0": a armadura de [fifths] depois de [transposition] (a linha da
/// biblioteca). Sem transposição, só a armadura original.
String keySignatureTransposed(int fifths, Transposition? transposition) =>
    transposition == null
    ? keySignatureShort(fifths)
    : '${keySignatureShort(fifths)} → '
          '${keySignatureShort(transposition.resultingFifths(fifths))}';

/// Um dos 12 tons da lista "Escolher…".
@immutable
class ToneChoice {
  const ToneChoice({
    required this.fifths,
    required this.name,
    required this.transposition,
  });

  /// A armadura do tom (quintas, + sustenidos).
  final int fifths;

  /// O nome do tom: "Ré".
  final String name;

  /// O que fazer para chegar nele; `null` no tom original da música.
  final Transposition? transposition;

  bool get isOriginal => transposition == null;

  /// "Ré · 2♯ · teclado −1", e na original "Mi♭ · 3♭ · original". Sem
  /// acidentes a armadura vai por extenso ("Dó · sem acidentes · teclado +3").
  String get label {
    final key = fifths == 0 ? 'sem acidentes' : keySignatureShort(fifths);
    final tail = switch (transposition) {
      null => 'original',
      final t => 'teclado ${t.keyboardLabel}',
    };
    return '$name · $key · $tail';
  }
}

/// Para qual tonalidade (quintas) cada um dos 12 tons vai, na ordem das
/// notas, de Dó a Si: o Fá♯ (6♯) fica com o trítono, que desce (D-TRP-DIRECAO).
const List<int> _toneFifths = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5];

/// Os 12 tons para uma música de armadura [fifths], do Dó ao Si, cada um com a
/// transposição que leva até ele (`null` no tom da própria música).
///
/// [lowest] e [highest] são a nota mais grave e a mais aguda da música
/// **original** (MIDI), para a direção caber no teclado
/// ([Transposition.toFifths]).
List<ToneChoice> toneChoices(
  int fifths, {
  required int lowest,
  required int highest,
  NoteNaming naming = NoteNaming.latin,
}) {
  final targets = [..._toneFifths];
  // A música em 6♭ (ou 7♯…) tem um tom que a lista não traz: ele entra no
  // lugar do tom enarmônico, que seria o mesmo teclado.
  if (!targets.contains(fifths)) {
    final enharmonic = targets.indexWhere((t) => (t - fifths) % 12 == 0);
    if (enharmonic >= 0) targets[enharmonic] = fifths;
  }
  return [
    for (final target in targets)
      ToneChoice(
        fifths: target,
        name: Transposition.keyName(target, naming: naming),
        transposition: Transposition.toFifths(
          fifths,
          target,
          lowest: lowest,
          highest: highest,
        ),
      ),
  ];
}

/// O selo da partitura transposta: "Mi♭ → Dó · teclado +3" ou, quando o som
/// é do app e não há nada a ajustar, "Mi♭ → Dó · o app toca no tom original".
String transposeSealText(
  int fifths,
  Transposition transposition, {
  required bool appIsSound,
  NoteNaming naming = NoteNaming.latin,
}) {
  final from = transposition.fromKeyName(fifths, naming: naming);
  final to = transposition.toKeyName(fifths, naming: naming);
  final tail = appIsSound
      ? 'o app toca no tom original'
      : 'teclado ${transposition.keyboardLabel}';
  return '$from → $to · $tail';
}

/// A pergunta antes de trocar de tom com trilha começada: "Em Dó a trilha
/// começa do zero. A do tom original fica guardada." [from] e [to] são os tons
/// (`null` = o original).
String toneChangeMessage(
  int fifths, {
  required Transposition? from,
  required Transposition? to,
  NoteNaming naming = NoteNaming.latin,
}) {
  final where = to == null
      ? 'No tom original'
      : 'Em ${to.toKeyName(fifths, naming: naming)}';
  final kept = from == null
      ? 'A do tom original'
      : 'A de ${from.toKeyName(fifths, naming: naming)}';
  return '$where a trilha começa do zero. $kept fica guardada.';
}

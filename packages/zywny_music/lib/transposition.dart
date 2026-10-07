import 'package:meta/meta.dart';

import 'note_name.dart' show Pitch, kHighestPianoMidi, kLowestPianoMidi;
import 'note_names.dart'
    show NoteNaming, kFlatSign, kSharpSign, noteLabel, pitchFromMidi;

/// Transpor a música para ler sem acidentes (fase Q, docs/plano/Q00): que
/// intervalo o Verovio usa, quanto vale no TRANSPOSE do teclado e como dizer
/// isso à pessoa. Só conta — não guarda, não renderiza, não toca em nada.
///
/// Uma transposição é o par (quintas, semitons):
///
///  * [fifthsDelta]: quantas quintas a armadura anda (de 3♭ a 0 são +3). É o
///    que decide a grafia — Mi♭ vira Dó, nunca Si♯ — e vale igual para maior e
///    menor;
///  * [semitones] (`k`): quanto a partitura sobe (+) ou desce (−). É o que
///    decide a oitava. `k ≡ 7 · fifthsDelta (mod 12)`, então só há duas
///    escolhas, uma para cada direção (`k` e `k ∓ 12`).
///
/// O teclado precisa de TRANSPOSE = [keyboard] = −`k`.
@immutable
class Transposition {
  const Transposition._(this.fifthsDelta, this.semitones);

  /// O tom da armadura [from] (quintas, + sustenidos) levado para [to].
  ///
  /// Das duas direções fica a de menor |k|; no trítono (|k| = 6), a que
  /// **desce** (D-TRP-DIRECAO). Se a música transposta — com a nota mais grave
  /// [lowest] e a mais aguda [highest] **da partitura original**, em número
  /// MIDI — sair de [keyLow]..[keyHigh], tenta a outra direção. Se nenhuma
  /// cabe, devolve a preferida e [fits] diz que não cabe (a tela avisa).
  ///
  /// `null` quando [from] == [to]: nada a transpor.
  static Transposition? toFifths(
    int from,
    int to, {
    required int lowest,
    required int highest,
    int keyLow = kLowestPianoMidi,
    int keyHigh = kHighestPianoMidi,
  }) {
    final delta = to - from;
    if (delta == 0) return null;
    final residue = (7 * delta) % 12; // 0..11, o k para cima
    final preferred = residue < 6 ? residue : residue - 12;
    final first = Transposition._(delta, preferred);
    // `k` = 0 com `delta` ≠ 0 é só trocar a grafia (Sol♭ ↔ Fá♯): sem outra
    // direção, a oitava não é o que se quer.
    if (preferred == 0) return first;
    final second = Transposition._(
      delta,
      preferred > 0 ? preferred - 12 : preferred + 12,
    );
    bool ok(Transposition t) => t.fits(
      lowest: lowest,
      highest: highest,
      keyLow: keyLow,
      keyHigh: keyHigh,
    );
    if (ok(first)) return first;
    return ok(second) ? second : first;
  }

  /// A armadura [fifths] levada para sem acidentes (Dó maior / Lá menor):
  /// `toFifths(fifths, 0)`. `null` quando já não tem acidentes.
  static Transposition? toNoAccidentals(
    int fifths, {
    required int lowest,
    required int highest,
    int keyLow = kLowestPianoMidi,
    int keyHigh = kHighestPianoMidi,
  }) => toFifths(
    fifths,
    0,
    lowest: lowest,
    highest: highest,
    keyLow: keyLow,
    keyHigh: keyHigh,
  );

  /// Lê o intervalo guardado, na sintaxe do Verovio (`-m3`, `P4`, `-A4`,
  /// `d5`, `A1`; `+` e minúsculas também valem). `null` se não é um intervalo
  /// simples que mude alguma coisa: `P3`, `m4`, `P8`, `P1`, `d1`…
  ///
  /// O que sai tem o texto canônico ([interval]): `p4` e `+P4` viram `P4`.
  static Transposition? parse(String text) {
    final match = _intervalPattern.firstMatch(text);
    if (match == null) return null;
    final down = match.group(1) == '-';
    final qualityText = match.group(2)!;
    final number = int.parse(match.group(3)!);
    if (number < 1 || number > 8) return null;

    final steps = (number - 1) % 7; // 0 = uníssono … 6 = sétima
    final octaves = (number - 1) ~/ 7;
    final perfect = _perfectFamily.contains(steps);
    final int quality; // 0 = perfeita/maior, 1 = aumentada, −1 = menor/dim.
    switch (qualityText[0]) {
      case 'P' || 'p':
        if (!perfect) return null;
        quality = 0;
      case 'M':
        if (perfect) return null;
        quality = 0;
      case 'm':
        if (perfect) return null;
        quality = -1;
      case 'A' || 'a':
        quality = qualityText.length;
      default: // d / D
        quality = perfect ? -qualityText.length : -qualityText.length - 1;
    }
    // Perfeita: P = 0, A×n = +n, d×n = −n. Maior/menor: M = 0, m = −1,
    // A×n = +n, d×n = −(n + 1): é o mesmo `quality`, somado à nota natural.
    final ascending = _naturalSemitones[steps] + 12 * octaves + quality;
    if (ascending < 0 || ascending >= 12) return null;
    final chain = _baseFifths[steps] + 7 * quality;
    final sign = down ? -1 : 1;
    final delta = sign * chain;
    final k = sign * ascending;
    if (delta == 0 && k == 0) return null;
    return Transposition._(delta, k);
  }

  /// Quantas quintas a armadura anda (+ = para o lado dos sustenidos).
  final int fifthsDelta;

  /// Quanto a partitura sobe (+) ou desce (−), em semitons.
  final int semitones;

  /// O valor do TRANSPOSE do teclado que devolve a música ao tom original.
  int get keyboard => -semitones;

  /// O intervalo na sintaxe da opção `transpose` do Verovio: `-m3`.
  ///
  /// Subindo, é o intervalo ascendente de [fifthsDelta] quintas; descendo, o
  /// intervalo (ascendente) de −[fifthsDelta], com o sinal de menos.
  String get interval {
    final down = semitones < 0 || (semitones == 0 && fifthsDelta > 0);
    final name = _ascendingName(down ? -fifthsDelta : fifthsDelta);
    return down ? '-$name' : name;
  }

  /// A armadura que sobra: [fifths] (da música) + [fifthsDelta].
  int resultingFifths(int fifths) => fifths + fifthsDelta;

  /// A música transposta cabe em [keyLow]..[keyHigh], dadas a nota mais grave
  /// [lowest] e a mais aguda [highest] **da original** (MIDI)?
  bool fits({
    required int lowest,
    required int highest,
    int keyLow = kLowestPianoMidi,
    int keyHigh = kHighestPianoMidi,
  }) => lowest + semitones >= keyLow && highest + semitones <= keyHigh;

  /// "+3", "−5" (sinal de menos tipográfico), "0": o que a pessoa digita no
  /// TRANSPOSE do teclado.
  String get keyboardLabel => switch (keyboard) {
    > 0 => '+$keyboard',
    < 0 => '−${-keyboard}',
    _ => '0',
  };

  /// O tom (maior) de uma armadura de [fifths] quintas: "Mi♭" para −3. O selo
  /// não diz o modo, então é sempre a tônica maior.
  static String keyName(int fifths, {NoteNaming naming = NoteNaming.latin}) =>
      _spell(fifths, naming);

  /// O tom de origem de uma música de armadura [fifths]: `keyName(fifths)`.
  String fromKeyName(int fifths, {NoteNaming naming = NoteNaming.latin}) =>
      _spell(fifths, naming);

  /// O tom para onde vai uma música de armadura [fifths]: "Dó" para
  /// `-m3` com −3.
  String toKeyName(int fifths, {NoteNaming naming = NoteNaming.latin}) =>
      _spell(resultingFifths(fifths), naming);

  /// "a tecla Dó vai soar Mi♭": o que soa quando o teclado está no
  /// [keyboard] certo e a pessoa aperta a tecla da altura escrita
  /// [writtenPitch] (MIDI). A grafia do som acompanha a da armadura (Mi♭, não
  /// Ré♯), como o selo.
  String soundsLike(int writtenPitch, {NoteNaming naming = NoteNaming.latin}) {
    final written = pitchFromMidi(writtenPitch);
    final key = _spell(_chainOf(written), naming);
    // O som anda as quintas ao contrário: de Dó a Mi♭ são −3 quando a
    // armadura andou +3.
    final sounding = _spell(_chainOf(written) - fifthsDelta, naming);
    return 'a tecla $key vai soar $sounding';
  }

  @override
  bool operator ==(Object other) =>
      other is Transposition &&
      other.fifthsDelta == fifthsDelta &&
      other.semitones == semitones;

  @override
  int get hashCode => Object.hash(fifthsDelta, semitones);

  @override
  String toString() => 'Transposition($interval, k=$semitones)';
}

final _intervalPattern = RegExp(
  r'^(-|\+?)([Pp]|M|m|[aA]+|[dD]+)([1-9][0-9]*)$',
);

// Os três arranjos abaixo são indexados pelo número do intervalo menos um:
// 0 = uníssono, 1 = segunda … 6 = sétima.

/// Uníssono, quarta e quinta têm a perfeita; as outras, a maior e a menor.
const _perfectFamily = {0, 3, 4};

/// Semitons do intervalo perfeito/maior.
const _naturalSemitones = [0, 2, 4, 5, 7, 9, 11];

/// Posição do intervalo perfeito/maior na cadeia de quintas (P1 = 0,
/// M2 = +2, M3 = +4, P4 = −1, P5 = +1, M6 = +3, M7 = +5). Cada aumento soma 7.
const _baseFifths = [0, 2, 4, -1, 1, 3, 5];

/// O intervalo ascendente cuja posição na cadeia de quintas é [chain]
/// ("M2" = +2, "m3" = −3, "A4" = +6, "d5" = −6, "A1" = +7).
String _ascendingName(int chain) {
  final steps = (4 * chain) % 7;
  final quality = (chain - _baseFifths[steps]) ~/ 7;
  final String name;
  if (_perfectFamily.contains(steps)) {
    name = quality == 0
        ? 'P'
        : quality > 0
        ? 'A' * quality
        : 'd' * -quality;
  } else {
    name = quality == 0
        ? 'M'
        : quality == -1
        ? 'm'
        : quality > 0
        ? 'A' * quality
        : 'd' * (-quality - 1);
  }
  // Diminuto de uníssono não existe: a oitava diminuta (d8, 11 semitons).
  final number = steps + 1 + (steps == 0 && quality < 0 ? 7 : 0);
  return '$name$number';
}

const _fifthsLetters = 'FCGDAEB';

/// A posição na cadeia de quintas de uma nota escrita ([Pitch] de
/// `pitchFromMidi`: pretas como sustenido): F = −1, C = 0, G = +1 … B = +5, e
/// +7 por sustenido.
int _chainOf(Pitch pitch) =>
    _fifthsLetters.indexOf(pitch.step) - 1 + 7 * pitch.alter;

/// O nome da nota na posição [chain] da cadeia de quintas, com a grafia que a
/// armadura de [chain] quintas dá à tônica maior: 0 = Dó, −3 = Mi♭, 6 = Fá♯.
String _spell(int chain, NoteNaming naming) {
  final shifted = chain + 1; // F = 0 … B = 6, e a cada 7 um acidente a mais
  final letter = _fifthsLetters[shifted % 7];
  final alter = (shifted - shifted % 7) ~/ 7; // divisão pelo piso
  final base = noteLabel(Pitch(letter, 0, 4), naming);
  return switch (alter) {
    > 0 => base + kSharpSign * alter,
    < 0 => base + kFlatSign * -alter,
    _ => base,
  };
}

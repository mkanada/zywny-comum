// EX17 — a grade de uma lead sheet: as cifras (`<harmony>`) de uma melodia do
// autor, cada uma com o compasso em que começa e a hora e a duração exatas. Dart
// puro: o validador do curso, a geração e a linha de comando a usam.
//
// A grade não é um `ChordChart`: esse divide cada compasso por igual, e a cifra
// do autor pode cair em qualquer tempo (uma troca no 2 de um 3/4). O juiz e a
// tela usam estes tempos como estão escritos.

import 'chord.dart';
import 'melody_xml.dart';

/// Um acorde da lead sheet: a cifra como o arquivo a escreveu (`label`, na
/// grafia da EX01), a cifra lida, o compasso (base 0) em que começa, e a hora e
/// a duração em semínimas desde o começo da peça.
class LeadChord {
  const LeadChord({
    required this.label,
    required this.chord,
    required this.bar,
    required this.start,
    required this.beats,
  });

  /// A cifra na grafia da EX01 (`C7M`, `Dm7(b5)`): é o que a tela e a revelação
  /// mostram.
  final String label;

  /// A cifra lida: as classes de altura e a fundamental.
  final ChordSymbol chord;

  /// O compasso (base 0) em que o acorde começa.
  final int bar;

  /// A hora em que o acorde começa, em semínimas desde o começo da peça.
  final double start;

  /// Quanto o acorde dura, em semínimas: até a cifra seguinte, ou o fim da peça.
  final double beats;
}

/// A grade de [melody]: uma [LeadChord] por cifra, na ordem, cada uma até a
/// seguinte (ou o fim da peça). Uma cifra repetida no mesmo tempo vale a última.
///
/// Devolve `null` com [error] (uma mensagem por erro, com o compasso) quando a
/// peça não tem cifra, quando o começo não tem acorde, quando uma cifra não se
/// lê ou quando o tipo de acorde não tem nome na grafia da EX01.
List<LeadChord>? leadSheetChords(
  MelodyScore melody, {
  void Function(String message)? error,
}) {
  final harmonies = melody.harmonies;
  if (harmonies.isEmpty) {
    error?.call('a partitura não tem cifras (`<harmony>`)');
    return null;
  }
  if (melody.measures.isEmpty) {
    error?.call('a partitura não tem compassos');
    return null;
  }
  final last = melody.measures.last;
  final end = last.start + last.beats;
  if (harmonies.first.start > 1e-9) {
    error?.call(
      'o compasso 1 não tem cifra: a primeira cifra tem de estar no '
      'começo da peça',
    );
    return null;
  }

  // A cifra de um tempo vale a última que o arquivo escreveu nele.
  final starts = <double, MelodyHarmony>{};
  for (final harmony in harmonies) {
    if (harmony.start >= end - 1e-9) continue;
    starts[harmony.start] = harmony;
  }
  final ordered = starts.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  final chords = <LeadChord>[];
  for (var k = 0; k < ordered.length; k++) {
    final harmony = ordered[k];
    final bar = melody.measureAt(harmony.start);
    final symbolText = harmony.symbol;
    if (symbolText == null) {
      error?.call(
        'o compasso ${bar + 1}: o tipo de acorde `${harmony.kind}` não tem '
        'nome na grafia da EX01 (use `text` no `<kind>`, como `7M`)',
      );
      return null;
    }
    String? problem;
    final chord = ChordSymbol.parse(
      symbolText,
      error: (message) {
        problem = message;
      },
    );
    if (chord == null) {
      error?.call(
        'o compasso ${bar + 1}: a cifra `$symbolText` não se lê'
        '${problem == null ? '' : ' ($problem)'}',
      );
      return null;
    }
    final next = k + 1 < ordered.length ? ordered[k + 1].start : end;
    chords.add(
      LeadChord(
        label: symbolText,
        chord: chord,
        bar: bar,
        start: harmony.start,
        beats: next - harmony.start,
      ),
    );
  }
  return chords;
}

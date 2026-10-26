// EX01, critério 5 — `progressions.dart`: todas as progressões da biblioteca
// resolvem em C, F♯ e B♭m sem erro, e a contagem de compassos bate com a do
// EX01 (seção 5). Também o leitor da progressão escrita no exercício.

import 'package:test/test.dart';
import 'package:zywny_music/chord_degree.dart';
import 'package:zywny_music/progressions.dart';

/// Compassos de cada progressão, como a tabela do EX01 os conta.
const _compassos = {
  'I-IV-V-I': 4,
  'I-V-vi-IV': 4,
  'I-vi-IV-V': 4,
  'vi-IV-I-V': 4,
  'ii-V-I': 4,
  'ii-V-i': 4,
  'blues-12': 12,
  'blues-12-quick': 12,
  'minor-blues': 12,
  'jazz-blues': 12,
  'circle-c': 8,
  'montuno-i-iv-v': 2,
  'turnaround': 2,
  'turnaround-sub': 2,
  'rhythm-changes-a': 8,
  'rhythm-changes-b': 8,
  'long-rhythm-changes-a': 16,
  'honeysuckle-a': 8,
  'honeysuckle-b': 8,
  'doxy-a': 8,
  'indiana-a': 16,
  'rose-room-a': 8,
  'pick-yourself-up-a': 8,
  'miss-jones-b': 8,
};

void main() {
  test('a biblioteca tem as 24 progressões da tabela, sem nome repetido', () {
    final nomes = [for (final p in kProgressions) p.name];
    expect(nomes.toSet(), hasLength(nomes.length));
    expect(nomes.toSet(), _compassos.keys.toSet());
  });

  for (final entrada in _compassos.entries) {
    test('${entrada.key} tem ${entrada.value} compassos e resolve em C, F♯ e '
        'B♭m', () {
      final progression = progressionNamed(entrada.key);
      expect(progression, isNotNull);
      expect(progression!.barCount, entrada.value);
      final bars = parseProgression(progression.chart);
      expect(bars, isNotNull);
      for (final tom in ['C', 'F#', 'Bbm']) {
        final key = KeySpec.parse(tom)!;
        for (final bar in bars!) {
          for (final degree in bar) {
            expect(degree.inKey(key).rootSpelling, isNotEmpty);
          }
        }
      }
    });
  }

  test('a progressão do exercício lê os mesmos compassos e graus', () {
    final bars = parseProgression('ii7 V7 | Imaj7');
    expect(bars, hasLength(2));
    expect(bars![0], hasLength(2));
    expect(bars[1].single.label, 'Imaj7');
  });

  test('um grau errado na progressão do exercício é recusado', () {
    String? erro;
    expect(parseProgression('ii7 xyz', error: (m) => erro = m), isNull);
    expect(erro, contains('`xyz`'));
  });

  test('long-rhythm-changes-a dobra cada acorde de rhythm-changes-a', () {
    final longa = progressionNamed('long-rhythm-changes-a')!;
    final curta = progressionNamed('rhythm-changes-a')!;
    final acordes = [for (final bar in curta.bars) ...bar];
    expect(longa.bars, [
      for (final acorde in acordes) [acorde],
    ]);
  });

  test('minor-blues em Bbm começa no Bbm7', () {
    final bars = parseProgression(progressionNamed('minor-blues')!.chart)!;
    expect(bars.first.first.inKey(KeySpec.parse('Bbm')!).rootSpelling, 'Bb');
  });
}

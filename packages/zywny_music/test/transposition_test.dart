// Q02, critério 1 — `Transposition`: as 14 linhas da tabela do Q00, os dois
// trítonos (com e sem estouro da faixa), `parse`, os nomes e a consistência
// de todos os pares de armaduras.

import 'package:test/test.dart';
import 'package:zywny_music/note_names.dart';
import 'package:zywny_music/transposition.dart';

/// Uma linha da tabela do Q00 ("Como escolher a transposição"): armadura
/// (quintas), intervalo do Verovio, `k` e o TRANSPOSE do teclado.
const _tabela = [
  (fifths: 1, interval: 'P4', k: 5, keyboard: -5),
  (fifths: 2, interval: '-M2', k: -2, keyboard: 2),
  (fifths: 3, interval: 'm3', k: 3, keyboard: -3),
  (fifths: 4, interval: '-M3', k: -4, keyboard: 4),
  (fifths: 5, interval: 'm2', k: 1, keyboard: -1),
  (fifths: 6, interval: '-A4', k: -6, keyboard: 6), // trítono: desce
  (fifths: 7, interval: '-A1', k: -1, keyboard: 1),
  (fifths: -1, interval: '-P4', k: -5, keyboard: 5),
  (fifths: -2, interval: 'M2', k: 2, keyboard: -2),
  (fifths: -3, interval: '-m3', k: -3, keyboard: 3),
  (fifths: -4, interval: 'M3', k: 4, keyboard: -4),
  (fifths: -5, interval: '-m2', k: -1, keyboard: 1),
  (fifths: -6, interval: '-d5', k: -6, keyboard: 6), // trítono: desce
  (fifths: -7, interval: 'A1', k: 1, keyboard: -1),
];

/// A faixa de uma música no meio do piano: nada estoura.
const _lowest = 48;
const _highest = 84;

void main() {
  group('a tabela do Q00', () {
    for (final linha in _tabela) {
      test('${linha.fifths.abs()}${linha.fifths > 0 ? '♯' : '♭'}: '
          '${linha.interval}, k=${linha.k}, teclado ${linha.keyboard}', () {
        final t = Transposition.toNoAccidentals(
          linha.fifths,
          lowest: _lowest,
          highest: _highest,
        )!;
        expect(t.interval, linha.interval);
        expect(t.semitones, linha.k);
        expect(t.keyboard, linha.keyboard);
        expect(t.fifthsDelta, -linha.fifths);
        expect(t.resultingFifths(linha.fifths), 0);
      });
    }

    test('são as 14 armaduras, e sem armadura não há o que transpor', () {
      expect(_tabela.map((l) => l.fifths).toSet(), {
        for (var f = -7; f <= 7; f++)
          if (f != 0) f,
      });
      expect(
        Transposition.toNoAccidentals(0, lowest: _lowest, highest: _highest),
        isNull,
      );
    });
  });

  group('a faixa do teclado', () {
    test('o trítono desce, salvo se sair da faixa', () {
      // 6♯ e 6♭ descem (D-TRP-DIRECAO).
      for (final fifths in [6, -6]) {
        final t = Transposition.toNoAccidentals(
          fifths,
          lowest: _lowest,
          highest: _highest,
        )!;
        expect(t.semitones, -6, reason: '$fifths');
      }
      // Descendo, a mais grave (A#0 = 22) iria a 16: sobe, que cabe.
      final sobe = Transposition.toNoAccidentals(6, lowest: 22, highest: 100)!;
      expect((sobe.interval, sobe.semitones), ('d5', 6));
      final sobeBemol = Transposition.toNoAccidentals(
        -6,
        lowest: 22,
        highest: 100,
      )!;
      expect((sobeBemol.interval, sobeBemol.semitones), ('A4', 6));
    });

    test('se nenhuma direção cabe, fica a preferida e `fits` diz que não', () {
      final t = Transposition.toNoAccidentals(6, lowest: 22, highest: 105)!;
      expect(t.semitones, -6);
      expect(t.fits(lowest: 22, highest: 105), isFalse);
      expect(t.fits(lowest: _lowest, highest: _highest), isTrue);
    });

    test('fora o trítono, só troca se a preferida estoura', () {
      // 1♯ sobe 5; com a mais aguda em 105 iria a 110: desce 7 (-P5).
      final desce = Transposition.toNoAccidentals(1, lowest: 40, highest: 105)!;
      expect((desce.interval, desce.semitones), ('-P5', -7));
      expect(desce.keyboard, 7);
      // 3♭ desce 3; com a mais grave em 23 iria a 20: sobe 9 (M6).
      final sobe = Transposition.toNoAccidentals(-3, lowest: 23, highest: 80)!;
      expect((sobe.interval, sobe.semitones), ('M6', 9));
      // O teclado de 61 teclas (C2–C7).
      final curto = Transposition.toNoAccidentals(
        -3,
        lowest: 40,
        highest: 94,
        keyLow: 36,
        keyHigh: 96,
      )!;
      expect(curto.semitones, -3);
      // Descer 3 estoura (37 − 3 = 34 < 36): sobe 9, que cabe.
      final sobe61 = Transposition.toNoAccidentals(
        -3,
        lowest: 37,
        highest: 80,
        keyLow: 36,
        keyHigh: 96,
      )!;
      expect(sobe61.semitones, 9);
      // Nenhuma cabe (94 + 9 = 103 > 96): fica a preferida.
      final nenhuma = Transposition.toNoAccidentals(
        -3,
        lowest: 37,
        highest: 94,
        keyLow: 36,
        keyHigh: 96,
      )!;
      expect(nenhuma.semitones, -3);
      expect(
        nenhuma.fits(lowest: 37, highest: 94, keyLow: 36, keyHigh: 96),
        isFalse,
      );
    });
  });

  group('qualquer tom', () {
    test('toFifths(f, 0) é toNoAccidentals(f)', () {
      for (var f = -7; f <= 7; f++) {
        expect(
          Transposition.toFifths(f, 0, lowest: _lowest, highest: _highest),
          Transposition.toNoAccidentals(f, lowest: _lowest, highest: _highest),
        );
      }
    });

    test('de um tom para ele mesmo não há o que transpor', () {
      for (var f = -7; f <= 7; f++) {
        expect(
          Transposition.toFifths(f, f, lowest: _lowest, highest: _highest),
          isNull,
        );
      }
    });

    test(
      'de Mi♭ (3♭) a Sol (1♯): quatro quintas, uma terça maior para cima',
      () {
        final t = Transposition.toFifths(
          -3,
          1,
          lowest: _lowest,
          highest: _highest,
        )!;
        expect((t.interval, t.semitones, t.keyboard), ('M3', 4, -4));
        expect(t.resultingFifths(-3), 1);
      },
    );

    test('os 225 pares: grafia, menor salto e o texto de volta pelo parse', () {
      for (var from = -7; from <= 7; from++) {
        for (var to = -7; to <= 7; to++) {
          final t = Transposition.toFifths(
            from,
            to,
            lowest: _lowest,
            highest: _highest,
          );
          if (from == to) {
            expect(t, isNull);
            continue;
          }
          final reason = '$from → $to';
          t!;
          expect(t.fifthsDelta, to - from, reason: reason);
          expect(t.resultingFifths(from), to, reason: reason);
          // k anda as quintas: 7 semitons cada.
          expect((t.semitones - 7 * (to - from)) % 12, 0, reason: reason);
          expect(t.semitones.abs(), lessThanOrEqualTo(6), reason: reason);
          // Quem guardou o texto reencontra a mesma transposição.
          expect(Transposition.parse(t.interval), t, reason: reason);
        }
      }
    });

    test('a outra direção também dá um texto que o parse devolve', () {
      for (var from = -7; from <= 7; from++) {
        for (var to = -7; to <= 7; to++) {
          if (from == to) continue;
          // As duas direções: com a mais grave na primeira tecla do piano,
          // descer estoura; com a mais aguda na última, subir estoura.
          final a = Transposition.toFifths(from, to, lowest: 21, highest: 60)!;
          final b = Transposition.toFifths(from, to, lowest: 60, highest: 108)!;
          for (final t in [a, b]) {
            expect(
              Transposition.parse(t.interval),
              t,
              reason: '$from → $to: ${t.interval}',
            );
            expect((t.semitones - 7 * (to - from)) % 12, 0);
          }
        }
      }
    });
  });

  group('parse', () {
    test('lê a sintaxe do Verovio', () {
      final casos = {
        '-m3': (-3, 3),
        'm3': (3, -3),
        '+M2': (2, 2),
        'P4': (5, -1),
        '-P4': (-5, 1),
        'p4': (5, -1),
        '-A4': (-6, -6),
        'A4': (6, 6),
        'd5': (6, -6),
        '-d5': (-6, 6),
        'A1': (1, 7),
        '-A1': (-1, -7),
        'AA1': (2, 14),
        'aa1': (2, 14),
        'd8': (11, -7),
        'm2': (1, -5),
        'P5': (7, 1),
        'M7': (11, 5),
        'm7': (10, -2),
      };
      casos.forEach((texto, esperado) {
        final t = Transposition.parse(texto);
        expect(t, isNotNull, reason: texto);
        expect((t!.semitones, t.fifthsDelta), esperado, reason: texto);
      });
    });

    test('o texto sai canônico', () {
      expect(Transposition.parse('+P4')!.interval, 'P4');
      expect(Transposition.parse('p4')!.interval, 'P4');
      expect(Transposition.parse('a4')!.interval, 'A4');
      expect(Transposition.parse('-D5')!.interval, '-d5');
    });

    test('recusa o que não é um intervalo simples que transponha', () {
      for (final texto in [
        '',
        '-',
        'm',
        '3',
        'x3',
        'P3', // não existe terça perfeita
        'M5', // nem quinta maior
        'm4',
        'M1',
        'P2',
        'P6',
        'P7',
        'P1', // nada a transpor
        '-P1',
        'd1', // não existe uníssono diminuto
        'P8', // oitava: só tom (fora do escopo)
        'M9',
        'A7', // 12 semitons = oitava
        'P0',
        'm03',
        ' m3',
        'm3 ',
        '--m3',
        '-+m3',
        'mm3',
        'PP4',
      ]) {
        expect(Transposition.parse(texto), isNull, reason: '"$texto"');
      }
    });
  });

  group('nomes para a tela', () {
    test('o tom maior de cada armadura (Dó-Ré-Mi)', () {
      const nomes = {
        -7: 'Dó♭',
        -6: 'Sol♭',
        -5: 'Ré♭',
        -4: 'Lá♭',
        -3: 'Mi♭',
        -2: 'Si♭',
        -1: 'Fá',
        0: 'Dó',
        1: 'Sol',
        2: 'Ré',
        3: 'Lá',
        4: 'Mi',
        5: 'Si',
        6: 'Fá♯',
        7: 'Dó♯',
      };
      nomes.forEach((fifths, nome) {
        expect(Transposition.keyName(fifths), nome, reason: '$fifths');
      });
    });

    test('e na grafia C-D-E', () {
      expect(Transposition.keyName(-3, naming: NoteNaming.letters), 'E♭');
      expect(Transposition.keyName(6, naming: NoteNaming.letters), 'F♯');
      expect(Transposition.keyName(0, naming: NoteNaming.letters), 'C');
    });

    test('além de 7 acidentes a grafia continua (dobrados)', () {
      expect(Transposition.keyName(8), 'Sol♯');
      expect(Transposition.keyName(-8), 'Fá♭');
      expect(Transposition.keyName(13), 'Fá♯♯');
      expect(Transposition.keyName(-13), 'Sol♭♭');
    });

    test('o selo: "Mi♭ → Dó · teclado +3"', () {
      final t = Transposition.toNoAccidentals(
        -3,
        lowest: _lowest,
        highest: _highest,
      )!;
      expect(t.fromKeyName(-3), 'Mi♭');
      expect(t.toKeyName(-3), 'Dó');
      expect(t.keyboardLabel, '+3');
    });

    test('o TRANSPOSE com sinal tipográfico', () {
      String label(int fifths) => Transposition.toNoAccidentals(
        fifths,
        lowest: _lowest,
        highest: _highest,
      )!.keyboardLabel;
      expect(label(-3), '+3');
      expect(label(1), '−5');
      expect(label(1), isNot(startsWith('-')));
      expect(label(6), '+6');
      expect(label(-7), '−1');
    });

    test('a tecla e o som: "a tecla Dó vai soar Mi♭"', () {
      Transposition de(int fifths) => Transposition.toNoAccidentals(
        fifths,
        lowest: _lowest,
        highest: _highest,
      )!;
      expect(de(-3).soundsLike(60), 'a tecla Dó vai soar Mi♭');
      expect(de(1).soundsLike(60), 'a tecla Dó vai soar Sol');
      expect(de(2).soundsLike(60), 'a tecla Dó vai soar Ré');
      expect(de(6).soundsLike(60), 'a tecla Dó vai soar Fá♯');
      expect(de(-6).soundsLike(60), 'a tecla Dó vai soar Sol♭');
      expect(de(7).soundsLike(60), 'a tecla Dó vai soar Dó♯');
      expect(de(-7).soundsLike(60), 'a tecla Dó vai soar Dó♭');
      // Outra tecla, e a oitava não conta.
      expect(de(-3).soundsLike(62), 'a tecla Ré vai soar Fá');
      expect(de(-3).soundsLike(48), 'a tecla Dó vai soar Mi♭');
      // Tecla preta escrita: Dó♯ em Mi♭→Dó soa Mi.
      expect(de(-3).soundsLike(61), 'a tecla Dó♯ vai soar Mi');
      expect(
        de(-3).soundsLike(60, naming: NoteNaming.letters),
        'a tecla C vai soar E♭',
      );
    });

    test('o som coincide com a conta em semitons, em todas as teclas', () {
      // A letra e o acidente do som, vistos como altura, são a escrita − k
      // (módulo 12): confere a grafia contra a soma de semitons.
      const pc = {
        'Dó': 0, 'Ré': 2, 'Mi': 4, 'Fá': 5, 'Sol': 7, 'Lá': 9, 'Si': 11, //
      };
      int pitchClass(String nome) {
        var alter = 0;
        var base = nome;
        while (base.endsWith('♯') || base.endsWith('♭')) {
          alter += base.endsWith('♯') ? 1 : -1;
          base = base.substring(0, base.length - 1);
        }
        return (pc[base]! + alter) % 12;
      }

      for (final linha in _tabela) {
        final t = Transposition.toNoAccidentals(
          linha.fifths,
          lowest: _lowest,
          highest: _highest,
        )!;
        for (var written = 60; written < 72; written++) {
          final texto = t.soundsLike(written);
          final som = texto.split(' vai soar ').last;
          expect(
            pitchClass(som),
            (written - t.semitones) % 12,
            reason: '${linha.interval}: $texto (escrita $written)',
          );
        }
      }
    });
  });
}

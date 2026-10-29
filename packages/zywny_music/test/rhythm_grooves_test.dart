// EX13 — `rhythm_grooves.dart`: a tabela dos grooves do `rhythm` com duas mãos,
// o leitor do molde e as figuras que se escrevem.

import 'package:test/test.dart';

import 'package:zywny_music/backing_styles.dart';
import 'package:zywny_music/rhythm_grooves.dart';

/// Os ataques de [bar] (`X` e `A`); os `-` que seguram não são ataques.
int _attacksOf(List<RhythmSymbol> bar) => bar
    .where((s) => s == RhythmSymbol.attack || s == RhythmSymbol.accent)
    .length;

/// As durações, em unidades, dos eventos de [bar] num compasso de [units]: um
/// ataque com os `-` que vêm depois (uma nota só), ou uma sequência de pausas.
List<int> _durationsOf(List<RhythmSymbol> bar, int units) {
  final step = units ~/ bar.length;
  final events = <List<RhythmSymbol>>[];
  for (final symbol in bar) {
    final joins =
        events.isNotEmpty &&
        (symbol == RhythmSymbol.hold ||
            (symbol == RhythmSymbol.rest &&
                events.last.first == RhythmSymbol.rest));
    if (joins) {
      events.last.add(symbol);
    } else {
      events.add([symbol]);
    }
  }
  return [for (final event in events) event.length * step];
}

void main() {
  group('os números do compasso', () {
    test('a semínima tem 12 unidades, e cada compasso tem as suas', () {
      expect(kRhythmUnitsPerQuarter, 12);
      expect(rhythmBarUnits('4/4'), 48);
      expect(rhythmBarUnits('3/4'), 36);
      expect(rhythmBarUnits('2/4'), 24);
      expect(rhythmBarUnits('6/8'), 36);
    });

    test('outro compasso lança ArgumentError', () {
      expect(() => rhythmBarUnits('5/4'), throwsArgumentError);
    });

    test('as figuras que se escrevem e as que não', () {
      for (final units in [2, 3, 4, 6, 8, 9, 12, 16, 18, 24, 32, 36, 48, 72]) {
        expect(rhythmNotatable(units), isTrue, reason: '$units');
      }
      for (final units in [0, 1, 5, 7, 10, 30, 42]) {
        expect(rhythmNotatable(units), isFalse, reason: '$units');
      }
    });
  });

  group('o leitor do molde', () {
    test('um molde de dois compassos, separado por |', () {
      final bars = parseRhythmMolde('X . . X | A . . .', time: '4/4');
      expect(bars, hasLength(2));
      expect(bars!.last.first, RhythmSymbol.accent);
    });

    test('sem o compasso, lê só a sintaxe', () {
      expect(parseRhythmMolde('X . | X .'), hasLength(2));
    });

    test('o `-` lê como hold, e o `.` é uma parte de silêncio', () {
      expect(parseRhythmMolde('X - . X')!.single, [
        RhythmSymbol.attack,
        RhythmSymbol.hold,
        RhythmSymbol.rest,
        RhythmSymbol.attack,
      ]);
    });

    test(
      'um `-` sem ataque antes dele dá erro (começo ou depois de pausa)',
      () {
        for (final line in ['- X . .', 'X . - X', 'X . . . | - . . .']) {
          final errors = <String>[];
          expect(
            parseRhythmMolde(line, time: '4/4', error: errors.add),
            isNull,
            reason: line,
          );
          expect(
            errors.single,
            contains('`-` segura uma nota: falta um ataque antes dele'),
            reason: line,
          );
        }
      },
    );

    test('símbolo desconhecido dá erro com o token', () {
      final errors = <String>[];
      expect(
        parseRhythmMolde('X . Z .', time: '4/4', error: errors.add),
        isNull,
      );
      expect(errors.single, contains('`Z`'));
    });

    test('compassos de tamanhos diferentes dão erro', () {
      final errors = <String>[];
      final bars = parseRhythmMolde(
        'X . . . | X . .',
        time: '4/4',
        error: errors.add,
      );
      expect(bars, isNull);
      expect(errors.single, contains('o compasso 2 tem 3 símbolos'));
    });

    test('número de símbolos que não divide o compasso dá erro', () {
      final errors = <String>[];
      expect(
        parseRhythmMolde('X . X . X', time: '4/4', error: errors.add),
        isNull,
      );
      expect(errors.single, contains('5 símbolos por compasso'));
    });

    test('uma pausa que não se escreve dá erro, com a conta', () {
      final errors = <String>[];
      // Oito colcheias: a pausa depois do 1 tem cinco colcheias (30 unidades).
      expect(
        parseRhythmMolde('X . . . . . X .', time: '4/4', error: errors.add),
        isNull,
      );
      expect(errors.single, contains('dura 30 unidades'));
      expect(errors.single, contains('ponha um ataque onde ela se divide'));
    });

    test('um ataque com `-` que segura uma figura que não se escreve dá erro', () {
      final errors = <String>[];
      // Um ataque e quatro `-` são cinco colcheias (30 unidades) numa nota só.
      expect(
        parseRhythmMolde('X - - - - . . .', time: '4/4', error: errors.add),
        isNull,
      );
      expect(errors.single, contains('o compasso 1'));
      expect(errors.single, contains('dura 30 unidades'));
    });

    test('a figura com `-` que cabe no compasso é válida', () {
      // Um ataque e três `-` são uma semibreve (48 unidades), num compasso só.
      expect(parseRhythmMolde('X - - - | . . . .', time: '4/4'), hasLength(2));
    });

    test('um compasso que não existe dá erro', () {
      final errors = <String>[];
      expect(
        parseRhythmMolde('X . . .', time: '5/4', error: errors.add),
        isNull,
      );
      expect(errors.single, contains('`5/4`'));
    });
  });

  group('a tabela', () {
    test('todo groove lê, e o molde divide o compasso do time', () {
      for (final groove in kRhythmGrooves) {
        final units = rhythmBarUnits(groove.time);
        final bars = groove.rightBars;
        expect(bars, isNotEmpty, reason: groove.name);
        expect(units % bars.first.length, 0, reason: groove.name);
        if (groove.left != null) {
          final left = groove.leftBars;
          expect(left, isNotEmpty, reason: groove.name);
          expect(units % left.first.length, 0, reason: groove.name);
        }
      }
    });

    test('todo groove tem só durações que se escrevem, nas duas mãos', () {
      for (final groove in kRhythmGrooves) {
        final units = rhythmBarUnits(groove.time);
        for (final hand in [groove.rightBars, groove.leftBars]) {
          for (final bar in hand) {
            for (final duration in _durationsOf(bar, units)) {
              expect(
                rhythmNotatable(duration),
                isTrue,
                reason: '${groove.name}: $duration unidades',
              );
            }
          }
        }
      }
    });

    test('hands é 1 sem a esquerda e 2 com ela', () {
      for (final groove in kRhythmGrooves) {
        expect(groove.hands, groove.left == null ? 1 : 2, reason: groove.name);
        expect(
          groove.leftBars,
          hasLength(groove.left == null ? 0 : groove.bars),
          reason: groove.name,
        );
      }
    });

    test('os nomes são únicos e vêm na ordem da tabela', () {
      expect(rhythmGrooveNames, [
        'two-against-three',
        'three-against-two',
        'clave-son-3-2',
        'clave-son-2-3',
        'clave-rumba-3-2',
        'bossa-clave',
        'samba-surdo',
        'ganza',
        'backbeat',
        'charleston',
      ]);
      expect(rhythmGrooveNames.toSet().length, rhythmGrooveNames.length);
    });

    test('um nome que não existe não acha nada', () {
      expect(rhythmGrooveNamed('nao-existe'), isNull);
      expect(rhythmGrooveNamed('ganza')!.name, 'ganza');
    });

    test('ganza: semicolcheias de uma mão, com A nas 4ªs de cada tempo', () {
      final ganza = rhythmGrooveNamed('ganza')!;
      expect(ganza.left, isNull);
      expect(ganza.hands, 1);
      final bar = ganza.rightBars.single;
      expect(bar, hasLength(16));
      expect(
        [
          for (var i = 0; i < bar.length; i++)
            if (bar[i] == RhythmSymbol.accent) i,
        ],
        [3, 7, 11, 15],
      );
    });

    test('two-against-three: 12 ataques na direita e 8 na esquerda', () {
      final groove = rhythmGrooveNamed('two-against-three')!;
      expect(_attacksOf(groove.rightBars.single), 12);
      expect(_attacksOf(groove.leftBars.single), 8);
    });

    test('samba-surdo: o surdo é uma mínima pontuada (12 e 36 unidades)', () {
      final groove = rhythmGrooveNamed('samba-surdo')!;
      expect(_durationsOf(groove.leftBars.single, 48), [12, 36]);
    });

    test('bossa-clave: a fundamental é semínima pontuada e colcheia', () {
      final groove = rhythmGrooveNamed('bossa-clave')!;
      expect(_durationsOf(groove.leftBars.first, 48), [18, 6, 18, 6]);
    });
  });

  group('o estilo six-eight', () {
    test('é achado por backingStyleNamed e tem 6 tokens', () {
      final style = backingStyleNamed('six-eight')!;
      expect(style.time, '6/8');
      expect(parseDrumLine(style.drums, slots: 6), hasLength(6));
      expect(bassSymbolsOf(style), hasLength(6));
    });
  });
}

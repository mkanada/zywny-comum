import 'package:test/test.dart';
import 'package:zywny_music/backing_styles.dart';
import 'package:zywny_music/comping_patterns.dart';

/// As posições (tempos da grade, base 0) de um golpe [letter] no molde [style].
List<int> _slotsOf(BackingStyle style, String letter) {
  final slots = parseDrumLine(style.drums, slots: style.grid * style.bars)!;
  return [
    for (var k = 0; k < slots.length; k++)
      if (slots[k].any((hit) => hit == kDrumPieces[letter])) k,
  ];
}

void main() {
  test(
    'todo molde de bateria cabe em grid × bars e só usa peças conhecidas',
    () {
      for (final style in kBackingStyles) {
        final slots = parseDrumLine(
          style.drums,
          slots: style.grid * style.bars,
        );
        expect(slots, isNotNull, reason: style.name);
      }
    },
  );

  test('todo molde de baixo cabe em grid × bars e fica no grau certo', () {
    for (final style in kBackingStyles) {
      if (style.bass == null) continue;
      final symbols = bassSymbolsOf(style);
      expect(symbols, isNotNull, reason: style.name);
      expect(symbols!.length, style.grid * style.bars, reason: style.name);
    }
  });

  test('os nomes dos estilos são únicos e a tabela os acha', () {
    expect(backingStyleNames.toSet().length, backingStyleNames.length);
    for (final name in backingStyleNames) {
      expect(backingStyleNamed(name)?.name, name);
    }
    expect(backingStyleNamed('nao-existe'), isNull);
  });

  test('straight: bumbo 1 e 3, caixa 2 e 4, chimbal em colcheias', () {
    final style = backingStyleNamed('straight')!;
    expect(_slotsOf(style, 'k'), [0, 4]);
    expect(_slotsOf(style, 's'), [2, 6]);
    expect(_slotsOf(style, 'h'), [0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test('salsa-3-2 e salsa-2-3: as claves nas posições do son (colcheias, 2 compassos)', () {
    // O son 3-2 tem três toques no primeiro compasso e dois no segundo; o 2-3
    // é o contrário. Em colcheias, com o compasso 2 começando na 8ª:
    //   3-2: x . . x . . x . | . . x . x . . .   → 0, 3, 6, 10, 12
    //   2-3: . . x . x . . . | x . . x . . x .   → 2, 4, 8, 11, 14
    expect(_slotsOf(backingStyleNamed('salsa-3-2')!, 'l'), [0, 3, 6, 10, 12]);
    expect(_slotsOf(backingStyleNamed('salsa-2-3')!, 'l'), [2, 4, 8, 11, 14]);
  });

  test('o estilo do molde de comping: valsa, seis-oito e shuffle', () {
    expect(backingStyleFor(compingPatternNamed('oom-pah-pah')!).name, 'waltz');
    expect(
      backingStyleFor(compingPatternNamed('six-eight-split')!).name,
      'six-eight',
    );
    expect(backingStyleFor(compingPatternNamed('boogie')!).name, 'shuffle');
    expect(backingStyleFor(compingPatternNamed('bossa-bounce')!).name, 'bossa');
    expect(backingStyleFor(compingPatternNamed('oom-pah')!).name, 'straight');
    expect(backingStyleFor(kAnyCompingPattern).name, 'straight');
  });

  test('parseDrumLine recusa molde do tamanho errado ou peça desconhecida', () {
    expect(parseDrumLine('k . s', slots: 4), isNull);
    expect(parseDrumLine('k . s Q', slots: 3), isNull);
    expect(parseDrumLine('k+h . s .', slots: 4), hasLength(4));
  });
}

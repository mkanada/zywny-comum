// EX11 — `comping_patterns.dart`: a biblioteca do `play-chart` e a leitura do
// molde em linha.

import 'package:test/test.dart';

import 'package:zywny_music/comping_patterns.dart';

void main() {
  group('a biblioteca', () {
    test('todo molde tem grid símbolos por compasso, nas duas mãos', () {
      for (final pattern in kCompingPatterns) {
        final left = parseCompingLine(
          pattern.left,
          grid: pattern.grid,
          error: (m) => fail('${pattern.name} (esquerda): $m'),
        );
        final right = parseCompingLine(
          pattern.right,
          grid: pattern.grid,
          error: (m) => fail('${pattern.name} (direita): $m'),
        );
        expect(left, isNotNull, reason: pattern.name);
        expect(right, isNotNull, reason: pattern.name);
        expect(left!.length, right!.length, reason: pattern.name);
        expect(pattern.bars, left.length, reason: pattern.name);
      }
    });

    test('os nomes são únicos e a tabela tem os 32 padrões', () {
      final names = compingPatternNames;
      expect(names.toSet().length, names.length);
      expect(names, hasLength(32));
    });

    test('o padrão de 3/4 tem grid de valsa, e o de 6/8 é de seis', () {
      expect(compingPatternNamed('oom-pah-pah')!.time, '3/4');
      expect(compingPatternNamed('oom-pah-pah')!.grid, 3);
      expect(compingPatternNamed('six-eight-split')!.time, '6/8');
      expect(compingPatternNamed('six-eight-split')!.grid, 6);
    });

    test('só os padrões de colcheias nascem com swing', () {
      final swinging = [
        for (final p in kCompingPatterns)
          if (p.swingDefault) p,
      ];
      expect(swinging.map((p) => p.name), [
        'boogie',
        'boogie-walking',
        'charleston',
        'jazz-in-2',
      ]);
      for (final p in swinging) {
        expect(p.grid, 8, reason: p.name);
      }
    });

    test('só o montuno tem dois compassos; os outros, um', () {
      final two = [
        for (final p in kCompingPatterns)
          if (p.bars == 2) p.name,
      ];
      expect(two, ['montuno']);
      expect(compingPatternNamed('montuno')!.leftBars, hasLength(2));
    });

    test('um nome que não existe não acha nada', () {
      expect(compingPatternNamed('oom-pa'), isNull);
    });
  });

  group('os símbolos', () {
    test('o baixo é o grau 1, e o grau acima de 9 cai uma oitava', () {
      expect(
        compingSymbolOf('B'),
        const CompingSymbol(CompingKind.degree, ['1']),
      );
      expect(compingDegreeOf('10'), '3');
      expect(compingDegreeOf('11'), '4');
      expect(compingDegreeOf('13'), '6');
      expect(compingDegreeOf('b7'), 'b7');
      expect(compingDegreeOf('#3'), '#3');
    });

    test('a fundamental e a 5ª juntas são um ataque só', () {
      expect(
        compingSymbolOf('1+5'),
        const CompingSymbol(CompingKind.dyad, ['1', '5']),
      );
    });

    test('os símbolos da regra de Rawlins são de cada tipo', () {
      expect(compingSymbolOf('.')!.isAttack, isFalse);
      expect(compingSymbolOf('C')!.kind, CompingKind.chord);
      expect(compingSymbolOf('T')!.kind, CompingKind.tone);
      expect(compingSymbolOf('X')!.kind, CompingKind.any);
      expect(compingSymbolOf('A')!.kind, CompingKind.approach);
    });

    test('o que não é símbolo volta nulo', () {
      expect(compingSymbolOf('Z'), isNull);
      expect(compingSymbolOf('14'), isNull);
      expect(compingSymbolOf('1+5+7'), isNull);
      expect(compingSymbolOf('c'), isNull);
    });
  });

  group('a leitura da linha', () {
    test('um molde de dois compassos, separado por |', () {
      final bars = parseCompingLine('1 . . . | 5 . . .', grid: 4);
      expect(bars, hasLength(2));
      expect(bars!.last.first.degrees, ['5']);
    });

    test('número de símbolos diferente de grid dá erro com a conta', () {
      final errors = <String>[];
      final bars = parseCompingLine('1 . . . .', grid: 4, error: errors.add);
      expect(bars, isNull);
      expect(errors.single, contains('tem 5 símbolos, e `grid` pede 4'));
    });

    test('símbolo desconhecido dá erro com o token', () {
      final errors = <String>[];
      expect(parseCompingLine('1 Z . .', grid: 4, error: errors.add), isNull);
      expect(errors.single, contains('`Z` não é um símbolo'));
    });
  });
}

// EX01, critério 2 — `ChordDegree` e `KeySpec`: o grau resolvido num tom, a
// grafia pelas quintas e a dominante secundária.

import 'package:test/test.dart';
import 'package:zywny_music/chord.dart';
import 'package:zywny_music/chord_degree.dart';

KeySpec _key(String texto) {
  final key = KeySpec.parse(texto);
  expect(key, isNotNull, reason: 'o tom `$texto`');
  return key!;
}

/// O grau [texto] no tom [tom], comparado com a cifra [esperada].
void _resolve(String texto, String tom, String esperada) {
  test('$texto em $tom é $esperada', () {
    final degree = ChordDegree.parse(texto);
    expect(degree, isNotNull, reason: '`$texto` deveria ser lido');
    expect(degree!.inKey(_key(tom)), ChordSymbol.parse(esperada));
  });
}

void main() {
  group('tons', () {
    test('lê a tônica, a grafia e o menor', () {
      final bbm = _key('Bbm');
      expect(bbm.tonic, 10);
      expect(bbm.minor, isTrue);
      expect(bbm.spelling, 'Bb');
      expect(_key('F#').tonic, 6);
      expect(_key('C').minor, isFalse);
    });

    test('um tom que não existe não é lido', () {
      String? erro;
      expect(KeySpec.parse('H', error: (m) => erro = m), isNull);
      expect(erro, contains('`H`'));
    });
  });

  group('graus no tom', () {
    _resolve('ii7', 'F', 'Gm7');
    _resolve('V7/vi', 'C', 'E7');
    _resolve('bVII', 'C', 'Bb');
    _resolve('V7', 'Am', 'E7');
    _resolve('iv', 'Am', 'Dm');
    _resolve('IV', 'Gb', 'Cb');
    _resolve('IV', 'F', 'Bb');
    _resolve('vii°', 'C', 'B°');
    _resolve('#iv°7', 'C', 'F#°7');
    _resolve('im7', 'C', 'Cm7');
    _resolve('Imaj7', 'Eb', 'Ebmaj7');
    _resolve('VII', 'Cm', 'Bb');
    _resolve('vii°', 'Cm', 'B°');
    _resolve('V7/V', 'C', 'D7');
    _resolve('iiø7', 'C', 'Dm7b5');
    _resolve('IVm', 'C', 'Fm');
    _resolve('iv7/bIII', 'C', 'Abm7');
    _resolve('I7', 'Bb', 'Bb7');
  });

  test('a alteração do grau é a do texto (b e #), nunca a da tabela', () {
    expect(ChordDegree.parse('bIII')!.inKey(_key('C')).rootSpelling, 'Eb');
    expect(ChordDegree.parse('#iv')!.inKey(_key('C')).rootSpelling, 'F#');
  });

  test('um grau que não existe é recusado, com mensagem', () {
    String? erro;
    expect(ChordDegree.parse('hello', error: (m) => erro = m), isNull);
    expect(erro, contains('`hello`'));
  });

  test('o texto canônico é o grau lido, sem as pontas', () {
    expect(ChordDegree.parse('  V7/vi ')!.label, 'V7/vi');
  });

  // EX04: a função de casa ou tensão. Só os graus que a pergunta usa têm uma.
  group('função (casa ou tensão)', () {
    DegreeFunction? funcaoDe(String texto) =>
        ChordDegree.parse(texto)!.harmonicFunction;

    test('I, iii e vi repousam; ii e IV afastam-se', () {
      for (final texto in ['I', 'iii', 'vi', 'Imaj7', 'vi7']) {
        expect(funcaoDe(texto), DegreeFunction.rest, reason: texto);
      }
      for (final texto in ['ii', 'IV', 'ii7', 'IVmaj7']) {
        expect(funcaoDe(texto), DegreeFunction.away, reason: texto);
      }
    });

    test('V, V7, vii° e a dominante secundária pedem resolução', () {
      for (final texto in ['V', 'V7', 'vii°', 'vii°7', 'V7/vi', 'V/V']) {
        expect(funcaoDe(texto), DegreeFunction.tension, reason: texto);
      }
    });

    test('o que não é casa nem tensão não tem função', () {
      for (final texto in ['I7', 'v', 'bVII', 'iv7/bIII', 'ii7/V']) {
        expect(funcaoDe(texto), isNull, reason: texto);
      }
    });
  });
}

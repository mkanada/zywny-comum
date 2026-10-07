// Q03: com que transposição uma música abre — a escolha dela, ou a chave
// geral "abrir as músicas já sem acidentes". As combinações música × chave
// geral, e a direção (a faixa do teclado) quando uma não cabe.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_library/piece.dart';
import 'package:zywny/settings/app_settings.dart';
import 'package:zywny/settings/effective_transposition.dart';
import 'package:zywny/settings/piece_settings.dart';

Piece _piece({int? fifths}) => Piece(
  number: 13,
  title: 'Hino',
  composer: 'Autor',
  fifths: fifths,
  titleKey: 'hino',
  composerKey: 'autor',
  searchKey: '13 hino',
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  AppSettings general({required bool byDefault}) =>
      AppSettings()..transposeByDefault = byDefault;

  String? interval(
    int? fifths, {
    String? choice,
    required bool byDefault,
    int? lowest,
    int? highest,
  }) {
    final t = lowest == null
        ? effectiveTransposition(
            _piece(fifths: fifths),
            PieceSettings(transpose: choice),
            general(byDefault: byDefault),
          )
        : effectiveTransposition(
            _piece(fifths: fifths),
            PieceSettings(transpose: choice),
            general(byDefault: byDefault),
            lowest: lowest,
            highest: highest!,
          );
    return t?.interval;
  }

  group('sem escolha da música', () {
    test('com a chave geral desligada, abre no tom original', () {
      for (final fifths in [-3, 0, 2, null]) {
        expect(interval(fifths, byDefault: false), isNull, reason: '$fifths');
      }
    });

    test('com a chave geral ligada, leva a armadura para sem acidentes', () {
      // A tabela do Q00: armadura → intervalo.
      const table = {
        1: 'P4',
        2: '-M2',
        3: 'm3',
        4: '-M3',
        -1: '-P4',
        -2: 'M2',
        -3: '-m3',
        -4: 'M3',
        -5: '-m2',
      };
      table.forEach((fifths, expected) {
        expect(interval(fifths, byDefault: true), expected, reason: '$fifths');
      });
      final transposition = effectiveTransposition(
        _piece(fifths: -3),
        const PieceSettings(),
        general(byDefault: true),
      )!;
      expect(transposition.semitones, -3);
      expect(transposition.keyboard, 3);
    });

    test('música sem armadura, ou já sem acidentes: a chave não age', () {
      expect(interval(null, byDefault: true), isNull);
      expect(interval(0, byDefault: true), isNull);
    });
  });

  group('com escolha da música', () {
    test('"Não" vence a chave geral', () {
      expect(interval(-3, choice: kTransposeNone, byDefault: true), isNull);
      expect(interval(-3, choice: kTransposeNone, byDefault: false), isNull);
    });

    test('um intervalo vale com a chave geral desligada ou ligada', () {
      expect(interval(-3, choice: '-m3', byDefault: false), '-m3');
      expect(interval(-3, choice: '-m3', byDefault: true), '-m3');
    });

    test('a escolha vence a chave geral, mesmo sendo outro tom', () {
      expect(interval(-3, choice: 'M2', byDefault: true), 'M2');
    });

    test('um intervalo não precisa da armadura da música', () {
      expect(interval(null, choice: 'P4', byDefault: false), 'P4');
      expect(interval(0, choice: '-M2', byDefault: false), '-M2');
    });
  });

  group('a faixa do teclado escolhe a direção da chave geral', () {
    test('sem a faixa da música, vale a do catálogo de hinos', () {
      expect(kCatalogLowestMidi, 27);
      expect(kCatalogHighestMidi, 86);
      // 6♯ (trítono): desce, e o catálogo cabe em qualquer direção.
      expect(
        effectiveTransposition(
          _piece(fifths: 6),
          const PieceSettings(),
          general(byDefault: true),
        )!.semitones,
        -6,
      );
    });

    test('a música que passaria do teclado ao descer, sobe', () {
      // Ré1 (26) desceria a Sol♯0 (20), abaixo do Lá0 (21).
      final low = effectiveTransposition(
        _piece(fifths: 6),
        const PieceSettings(),
        general(byDefault: true),
        lowest: 26,
        highest: 80,
      )!;
      expect(low.semitones, 6);
      expect(low.fifthsDelta, -6);

      // 1♯ sobe uma quarta (+5); com a nota mais aguda em Lá7 (105) passaria
      // do Dó8 (108), então desce uma quinta (−7).
      final high = effectiveTransposition(
        _piece(fifths: 1),
        const PieceSettings(),
        general(byDefault: true),
        lowest: 40,
        highest: 105,
      )!;
      expect(high.semitones, -7);
      expect(high.fifthsDelta, -1);
    });

    test('a escolha da música não muda de direção por causa da faixa', () {
      expect(
        interval(6, choice: 'A4', byDefault: true, lowest: 26, highest: 80),
        'A4',
      );
    });
  });
}

// Testes de R04a — fontes e resolução de `family` (§5.4).
//
// Cobre os critérios de aceite 2-4 do passo, com as TTFs carregadas pelo
// helper `support/load_fonts.dart` e a largura de referência calculada das
// métricas da própria TTF (`support/ttf_metrics.dart`).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/ttf_metrics.dart';

/// A string do critério 3, a um tamanho típico de título do corpus.
const _probeString = 'Allegro molto agitato.';
const _probeSize = 405.0;

double _painterWidth({
  FontStyle style = FontStyle.normal,
  FontWeight weight = FontWeight.w400,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: _probeString,
      style: TextStyle(
        fontFamily: kScoreTextFamily,
        fontSize: _probeSize,
        fontStyle: style,
        fontWeight: weight,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  test('mapeamento: Times, Times+serif e desconhecidos viram a serifada', () {
    expect(resolveFamily('Times'), kScoreTextFamily);
    expect(resolveFamily('Times, serif'), kScoreTextFamily);
    expect(resolveFamily('qualquer coisa'), kScoreTextFamily);
    expect(kScoreTextFamily, 'Liberation Serif');
    expect(kScoreTextFamilyPackage, 'score_bridge');
  });

  group('com fontes carregadas', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await loadScoreFonts();
    });

    test('antifallback: TextPainter bate com hmtx/head (<1%)', () async {
      final bytes = await rootBundle.load(kScoreFontAssets[0]);
      final ttf = TtfAdvances.parse(
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final expected = ttf.widthOf(_probeString, _probeSize);
      final actual = _painterWidth();
      final diff = (actual - expected).abs() / expected;
      expect(diff, lessThan(0.01));
    });

    test('4 estilos: mesma string, 4 larguras diferentes', () {
      final widths = {
        _painterWidth(),
        _painterWidth(style: FontStyle.italic),
        _painterWidth(weight: FontWeight.w700),
        _painterWidth(style: FontStyle.italic, weight: FontWeight.w700),
      };
      expect(widths, hasLength(4));
    });
  });
}

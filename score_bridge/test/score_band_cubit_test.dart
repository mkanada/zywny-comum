// `ScoreBandCubit` (BL25): as faixas da partitura. Cada troca avisa, até com a
// mesma lista (como o `ChangeNotifier` avisava), e o `serial` sobe a cada aviso.
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _fill = ui.Color(0x331E6FD9);
const _label = ui.Color(0xFF1E6FD9);
const _band = ScoreBand(['orw55dt'], label: 'você');

ScoreBandCubit _cubit() => ScoreBandCubit(fill: _fill, labelColor: _label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScoreBandCubit', () {
    blocTest<ScoreBandCubit, ScoreBandState>(
      'trocar as faixas avisa uma vez, com o serial seguinte',
      build: _cubit,
      act: (c) => c.bands = const [_band],
      expect: () => [
        isA<ScoreBandState>()
            .having((s) => s.bands, 'bands', const [_band])
            .having((s) => s.serial, 'serial', 1),
      ],
    );

    blocTest<ScoreBandCubit, ScoreBandState>(
      'limpar duas vezes avisa as duas, mesmo com a lista vazia (renotificação)',
      build: _cubit,
      act: (c) {
        c.clear();
        c.clear();
      },
      expect: () => [
        isA<ScoreBandState>().having((s) => s.serial, 'serial', 1),
        isA<ScoreBandState>().having((s) => s.serial, 'serial', 2),
      ],
    );

    blocTest<ScoreBandCubit, ScoreBandState>(
      'as cores (fundo e aviso) são as do construtor e não mudam com as faixas',
      build: _cubit,
      act: (c) => c.bands = const [_band],
      verify: (c) {
        expect(c.fill, _fill);
        expect(c.labelColor, _label);
        expect(c.bands, const [_band]);
      },
    );

    test('trocar as faixas depois do close não lança nem avisa', () async {
      final c = _cubit();
      await c.close();
      c.bands = const [_band];
      expect(c.bands, isEmpty, reason: 'fechado: a troca não tem efeito');
      expect(c.state.serial, 0);
    });
  });
}

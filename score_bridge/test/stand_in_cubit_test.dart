// `StandInCubit` (BL25): as pausas substitutas. Trocar as colunas avisa sempre
// (como o `ChangeNotifier` avisava); o que não tem nada a tirar não avisa; e
// depois do close nada avisa nem lança.
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _rest = ui.Color(0xFF7B1FA2);
const _flash = ui.Color(0xFFD32F2F);

StandInCubit _cubit() => StandInCubit(restColor: _rest);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StandInCubit', () {
    blocTest<StandInCubit, StandInState>(
      'trocar as colunas avisa, mesmo com as mesmas colunas (renotificação)',
      build: _cubit,
      act: (c) {
        c.setColumns({1: const ['a'], 2: const ['b']});
        c.setColumns({1: const ['a'], 2: const ['b']});
      },
      expect: () => [
        isA<StandInState>().having((s) => s.serial, 'serial', 1),
        isA<StandInState>().having((s) => s.serial, 'serial', 2),
      ],
      verify: (c) {
        expect(c.keys, [1, 2]);
        expect(c.colorOf(1), _rest, reason: 'sem piscar, a cor é a de repouso');
      },
    );

    blocTest<StandInCubit, StandInState>(
      'limpar sem pausa, tirar uma chave que não existe e piscar uma chave '
      'que não existe não avisam',
      build: _cubit,
      act: (c) {
        c.clear();
        c.remove(9);
        c.flash(9, _flash);
      },
      expect: () => const <StandInState>[],
    );

    blocTest<StandInCubit, StandInState>(
      'trocar os compassos escondidos avisa',
      build: _cubit,
      act: (c) => c.setMeasures(const []),
      expect: () => [isA<StandInState>().having((s) => s.serial, 'serial', 1)],
    );

    test('depois do close, trocar as colunas não avisa nem lança', () async {
      final c = _cubit();
      await c.close();
      c.setColumns({1: const ['a']});
      expect(c.state.serial, 0);
    });
  });
}

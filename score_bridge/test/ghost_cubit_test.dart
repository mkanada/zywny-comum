// `GhostCubit` (BL25): as fantasmas das teclas erradas. Cada mudança avisa uma
// vez; o que não muda não avisa; depois do close nada avisa e nada lança.
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _chord = ['orw55dt', 'q1t6l0ej', 'r1c5f34m'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VsbDocument doc;
  setUpAll(() {
    doc = VsbDocument.fromBytes(
      File('test/fixtures/fantasma/satie.vsb').readAsBytesSync(),
    );
  });

  group('GhostCubit', () {
    blocTest<GhostCubit, GhostState>(
      'o evento esperado muda uma vez; o mesmo evento não avisa',
      build: GhostCubit.new,
      act: (c) {
        c.setExpected(['a']);
        c.setExpected(['a']);
      },
      expect: () => [isA<GhostState>().having((s) => s.serial, 'serial', 1)],
    );

    blocTest<GhostCubit, GhostState>(
      'apertar uma tecla errada e soltá-la avisa a cada passo',
      build: () => GhostCubit()..attachDocument(doc),
      act: (c) {
        c.setExpected(_chord);
        c.press(70);
        c.release(70);
      },
      expect: () => [
        isA<GhostState>().having((s) => s.serial, 'serial', 1),
        isA<GhostState>().having((s) => s.serial, 'serial', 2),
        isA<GhostState>().having((s) => s.serial, 'serial', 3),
      ],
      verify: (c) => expect(c.visible.single.ghost.key, 70),
    );

    blocTest<GhostCubit, GhostState>(
      'limpar sem nada e limpar a revisão vazia não avisam',
      build: GhostCubit.new,
      act: (c) {
        c.clear();
        c.clearReview();
      },
      expect: () => const <GhostState>[],
    );

    blocTest<GhostCubit, GhostState>(
      'setReview avisa mesmo com a lista vazia (a troca sempre avisou)',
      build: GhostCubit.new,
      act: (c) => c.setReview(const []),
      expect: () => [isA<GhostState>().having((s) => s.serial, 'serial', 1)],
    );

    test('depois do close, apertar uma tecla não avisa nem lança', () async {
      final c = GhostCubit();
      await c.close();
      c.press(1);
      c.setReview(const []);
      expect(c.state.serial, 0);
    });
  });
}

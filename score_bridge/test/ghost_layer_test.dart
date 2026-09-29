// Ciclo de vida das fantasmas (D-FANT-DURACAO): aparece no note-on, fica ao
// menos `minVisible`, some com fade depois do note-off.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  late VsbDocument doc;
  setUpAll(() {
    doc = VsbDocument.fromBytes(
      File('test/fixtures/fantasma/satie.vsb').readAsBytesSync(),
    );
  });

  const chord = ['orw55dt', 'q1t6l0ej', 'r1c5f34m'];

  test('aparece no note-on, respeita o mínimo e some com fade', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    var now = Duration.zero;
    final c = GhostController()
      ..nowOverride = (() => now)
      ..attachDocument(doc)
      ..setExpected(chord);
    addTearDown(c.dispose);

    c.press(70);
    expect(c.visible.single.ghost.key, 70);
    expect(c.visible.single.opacity, 1);

    now = const Duration(milliseconds: 50);
    c.release(70); // antes do mínimo: continua opaca até 250 ms
    now = const Duration(milliseconds: 200);
    c.tickForTest();
    expect(c.visible.single.opacity, 1);

    now = const Duration(milliseconds: 325); // 75 ms de 150 ms de fade
    c.tickForTest();
    expect(c.visible.single.opacity, closeTo(0.5, 0.01));

    now = const Duration(milliseconds: 500);
    c.tickForTest();
    expect(c.isEmpty, isTrue);
  });

  test('teclas simultâneas colidem entre si; sem esperado, nada', () {
    final c = GhostController()..attachDocument(doc);
    addTearDown(c.dispose);
    c.press(70);
    expect(c.isEmpty, isTrue); // sem evento esperado ainda
    c.setExpected(chord);
    c.press(70);
    c.press(71);
    expect(c.visible.map((v) => v.ghost.key), [70, 71]);
  });
}

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

  group('tecla fora do tempo', () {
    test('com alvo próprio, sem esperado global: antes à esquerda, depois à direita', () {
      final c = GhostController()..attachDocument(doc);
      addTearDown(c.dispose);
      c.press(70, targetIds: chord);
      final onTime = c.visible.single.ghost;
      c.clear();
      c.press(70, targetIds: chord, side: -1);
      final before = c.visible.single.ghost;
      c.clear();
      c.press(70, targetIds: chord, side: 1);
      final after = c.visible.single.ghost;
      expect(before.head.x, lessThan(onTime.head.x));
      expect(after.head.x, greaterThan(onTime.head.x));
      expect(before.head.y, onTime.head.y);
      expect(
        onTime.head.x - before.head.x,
        closeTo(after.head.x - onTime.head.x, 1e-6),
      );
      // O deslocamento leva as linhas suplementares junto.
      for (var i = 0; i < onTime.ledgers.length; i++) {
        expect(
          after.ledgers[i].x1 - onTime.ledgers[i].x1,
          closeTo(after.head.x - onTime.head.x, 1e-6),
        );
      }
    });
  });

  group('revisão', () {
    test('fica fixa: não some com clear nem com o fade', () {
      var now = Duration.zero;
      final c = GhostController()
        ..nowOverride = (() => now)
        ..attachDocument(doc);
      addTearDown(c.dispose);
      c.setReview(const [
        GhostRequest(key: 70, targetIds: chord, side: -1),
        GhostRequest(key: 70, targetIds: chord, side: 1),
        // Repetido: vale um só.
        GhostRequest(key: 70, targetIds: chord, side: 1),
      ]);
      expect(c.review, hasLength(2));
      expect(c.visible.map((v) => v.opacity), [1, 1]);
      expect(c.isEmpty, isFalse);

      c.clear(); // fim do treino
      now = const Duration(seconds: 10);
      c.tickForTest();
      expect(c.visible, hasLength(2));

      c.clearReview();
      expect(c.isEmpty, isTrue);
    });

    test('um documento novo refaz as fantasmas da revisão', () {
      final c = GhostController()..attachDocument(doc);
      addTearDown(c.dispose);
      c.setReview(const [GhostRequest(key: 70, targetIds: chord)]);
      final first = c.review.single;
      final other = VsbDocument.fromBytes(
        File('test/fixtures/fantasma/satie.vsb').readAsBytesSync(),
      );
      c.attachDocument(other);
      expect(c.review, hasLength(1));
      expect(c.review.single.head.x, first.head.x);
    });
  });
}

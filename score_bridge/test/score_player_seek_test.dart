// `ScorePlayer.seekToElement` (E02c): tocar a partir de um elemento
// repetido, com a política D-TOQUE (decisão do usuário em 2026-09-22: a
// mesma passagem da posição atual, senão a 1ª).
//
// O Ticker do controller/player não pode sobreviver ao teste, e
// `addTearDown` roda tarde demais para a verificação do binding (mesma
// armadilha documentada em score_player_test.dart): a limpeza vai num
// `finally`, não em `addTearDown`.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

List<String> _measureOrder(VsbDocument doc) {
  final order = <String>[];
  void walk(SceneNode n) {
    if (n.className == 'measure' && n.id != null) {
      order.add(n.id!);
    }
    for (final c in n.children) {
      if (c is SceneNode) walk(c);
    }
  }

  for (final p in doc.pages) {
    walk(p.root);
  }
  return order;
}

void main() {
  // Medido com --xml-id-seed 42 (docs/plano/E02c, notas de execução):
  // compasso 5 = 'jbxc50u', nota = 'i88ib9g'. Onset da passagem 1: 9474 ms;
  // da passagem 2 (dentro da repetição, 92368-165789 ms): 101842 ms.
  const notaCompasso5 = 'i88ib9g';

  Future<void> withPlayer(
    VsbDocument doc,
    Future<void> Function(ScoreController controller, ScorePlayer player) body,
  ) async {
    final controller = ScoreController(document: doc);
    final player = ScorePlayer(document: doc, controller: controller);
    try {
      await body(controller, player);
    } finally {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    }
  }

  test('onsetsOf: a nota do compasso 5 tem as duas passagens', () {
    final doc = _fixture('erik-satie.vsb');
    final tl = ScoreTimeline(doc);
    final onsets = tl.onsetsOf(notaCompasso5);
    expect(onsets, hasLength(2));
    expect(onsets[0], (pass: 1, ms: 9474.0));
    expect(onsets[1], (pass: 2, ms: 101842.0));
  });

  test('onsetsOf: id expandido devolve só a sua passagem; compasso 32 (casa 1) só 1', () {
    final doc = _fixture('erik-satie.vsb');
    final tl = ScoreTimeline(doc);
    expect(tl.onsetsOf('$notaCompasso5-rend2'), [(pass: 2, ms: 101842.0)]);
    // Compasso 32 é o início da casa 1 (E01a): toca uma vez só.
    final compasso32 = _measureOrder(doc)[31];
    expect(tl.occurrencesOf(compasso32), hasLength(1));
  });

  testWidgets('seekToElement na nota do compasso 5, sem pass: (critério 1)', (
    tester,
  ) async {
    final doc = _fixture('erik-satie.vsb');
    await withPlayer(doc, (controller, player) async {
      player.seek(const Duration(milliseconds: 10000));
      expect(player.seekToElement(notaCompasso5), isTrue);
      expect(player.position, const Duration(milliseconds: 9474));

      player.seek(const Duration(milliseconds: 100000));
      expect(player.seekToElement(notaCompasso5), isTrue);
      expect(player.position, const Duration(milliseconds: 101842));

      player.seek(const Duration(milliseconds: 170000));
      expect(player.seekToElement(notaCompasso5), isTrue);
      expect(player.position, const Duration(milliseconds: 9474));
    });
  });

  testWidgets(
    'pass: explícito ganha da política; pass inexistente falha sem mexer',
    (tester) async {
      final doc = _fixture('erik-satie.vsb');
      await withPlayer(doc, (controller, player) async {
        player.seek(const Duration(milliseconds: 10000));
        expect(player.seekToElement(notaCompasso5, pass: 2), isTrue);
        expect(player.position, const Duration(milliseconds: 101842));

        final before = player.position;
        expect(player.seekToElement(notaCompasso5, pass: 3), isFalse);
        expect(player.position, before);
      });
    },
  );

  testWidgets('id desconhecido: false, sem mexer na posição', (tester) async {
    final doc = _fixture('erik-satie.vsb');
    await withPlayer(doc, (controller, player) async {
      player.seek(const Duration(milliseconds: 5000));
      final before = player.position;
      expect(player.seekToElement('nao-existe'), isFalse);
      expect(player.position, before);
    });
  });

  testWidgets('id expandido sem pass: vai para a passagem 2', (tester) async {
    final doc = _fixture('erik-satie.vsb');
    await withPlayer(doc, (controller, player) async {
      player.seek(const Duration(milliseconds: 10000)); // passagem 1 aqui
      expect(player.seekToElement('$notaCompasso5-rend2'), isTrue);
      expect(player.position, const Duration(milliseconds: 101842));
    });
  });

  testWidgets(
    'nota de ocorrência única (casa 1): vai para ela de qualquer posição',
    (tester) async {
      final doc = _fixture('erik-satie.vsb');
      final tl = ScoreTimeline(doc);
      final compasso32 = _measureOrder(doc)[31];
      final noteOnce =
          tl.measures[tl.occurrencesOf(compasso32).single].noteIds.first;
      final onset = tl.onsetsOf(noteOnce).single;

      await withPlayer(doc, (controller, player) async {
        for (final startMs in [0, 50000, 120000, 170000]) {
          player.seek(Duration(milliseconds: startMs));
          expect(player.seekToElement(noteOnce), isTrue);
          expect(player.position, Duration(milliseconds: onset.ms.round()));
        }
      });
    },
  );

  testWidgets('toque via onElementTap chama seekToElement e destaca a nota', (
    tester,
  ) async {
    final doc = _fixture('erik-satie.vsb');
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await withPlayer(doc, (controller, player) async {
      player.seek(const Duration(milliseconds: 10000));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScorePageView(
            document: doc,
            pageIndex: 0,
            controller: controller,
            onElementTap: (id) => player.seekToElement(id),
          ),
        ),
      );
      await tester.pump();

      final ref = doc.geometry.elementOf(notaCompasso5)!;
      final page = doc.pages[0];
      final px = pageRectToPagePx(ref.bbox, page);
      final scale =
          tester.getSize(find.byType(ScorePageView)).width / page.widthPx;
      final tapPoint = Offset(
        (px.left + px.right) / 2 * scale,
        (px.top + px.bottom) / 2 * scale,
      );
      final topLeft = tester.getTopLeft(find.byType(ScorePageView));
      await tester.tapAt(topLeft + tapPoint);
      await tester.pump();

      expect(player.position, const Duration(milliseconds: 9474));
      expect(controller.isHighlighted(notaCompasso5), isTrue);

      // desmonta antes do finally desligar o controller/player, para não
      // deixar o widget vivo além do teste.
      await tester.pumpWidget(const SizedBox());
    });
  });
}

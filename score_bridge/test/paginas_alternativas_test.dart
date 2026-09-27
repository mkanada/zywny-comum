// Portão da fase P (P05): páginas alternativas de ponta a ponta, sobre as
// 23 fixtures de `repeticoes/` (agora regeneradas com `alternates.json`,
// P05) — invariantes de P04a e reprodução completa das peças com
// repetição de verdade.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

const _fixturesDir = 'test/fixtures/repeticoes';

/// As mesmas peças com repetição de verdade de `repeticoes_test.dart`
/// (E05) — as únicas com um `ScorePlayer` do início ao fim aqui também.
const _piecesWithRepeats = [
  'Erik_Satie_-_Gymnopedie_No.1',
  'Maple_Leaf_Rag_Scott_Joplin',
  'Chopin_Mazurka_Op6_No1',
  'Grieg_Butterfly_Op43_No1',
  'Grieg_Little_bird_Op43_No4',
  'Scarlatti_Sonata_in_C-major',
];

List<File> _fixtures() =>
    Directory(_fixturesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.vsb'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('$_fixturesDir/$name.vsb').readAsBytesSync());

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('pré-condição: 23 fixtures, pelo menos uma com alternates.json', () {
    final fixtures = _fixtures();
    expect(fixtures.length, 23);
    final withAlternates = fixtures.where((f) {
      final doc = VsbDocument.fromBytes(f.readAsBytesSync());
      return doc.alternates.isNotEmpty;
    });
    expect(withAlternates, isNotEmpty);
  });

  group('invariantes de P04a nas 23 fixtures', () {
    test('toda ocorrência existe na página view', () {
      for (final file in _fixtures()) {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        final tl = ScoreTimeline(doc);
        for (final m in tl.measures) {
          final page = doc.geometryOf(m.view.sequence).pageOf(m.id);
          expect(
            page,
            m.view.index,
            reason: '${file.uri.pathSegments.last} ${m.id} ${m.view}',
          );
        }
      }
    });

    test('view só muda em fronteira de página da mesma sequência ou salto', () {
      for (final file in _fixtures()) {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        final tl = ScoreTimeline(doc);
        for (var i = 1; i < tl.measures.length; i++) {
          final m = tl.measures[i];
          final prev = tl.measures[i - 1];
          if (m.view == prev.view) {
            continue;
          }
          final sameSequenceTurn = m.view.sequence == prev.view.sequence;
          expect(
            m.isJump || sameSequenceTurn,
            isTrue,
            reason:
                '${file.uri.pathSegments.last} ${prev.id}(${prev.view}) -> '
                '${m.id}(${m.view}) isJump=${m.isJump}',
          );
        }
      }
    });

    test('todo salto para view diferente com sequência disponível cai com o '
        'destino como 1º compasso da página exibida', () {
      var checked = 0;
      for (final file in _fixtures()) {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        final tl = ScoreTimeline(doc);
        for (var i = 1; i < tl.measures.length; i++) {
          final m = tl.measures[i];
          final prev = tl.measures[i - 1];
          if (!m.isJump || m.view == prev.view) {
            continue;
          }
          // Salto que muda de view: o destino tem que ser o 1º compasso
          // da página exibida — normal (`_pageOfMeasure`/`firstMeasureId`
          // de `document.pages`) ou de uma sequência alternativa
          // (`AlternateSequence.pages[k].firstMeasureId`), conforme o
          // passo "b"/"c"/"d" da regra de P00 que resolveu esta troca.
          final page = doc.pageAt(m.view);
          expect(
            page.firstMeasureId,
            m.id,
            reason:
                '${file.uri.pathSegments.last} salto para ${m.id} caiu em '
                '${m.view}, que não começa nele',
          );
          checked++;
        }
      }
      expect(
        checked,
        greaterThan(0),
        reason:
            'pré-condição: alguma fixture precisa ter um salto que '
            'muda de view',
      );
    });
  });

  group('ScorePlayer do início ao fim a 4x em pagedSweep, sem exceção', () {
    for (final name in _piecesWithRepeats) {
      testWidgets(name, (tester) async {
        final doc = _fixture(name);
        final controller = ScoreController(document: doc);
        final vc = ScoreViewController();
        await pumpAtSize(
          tester,
          Directionality(
            textDirection: TextDirection.ltr,
            child: ScoreView(
              document: doc,
              controller: controller,
              viewController: vc,
            ),
          ),
          doc.pages[0].widthPx,
          doc.pages[0].heightPx,
        );
        final state = tester.state<ScoreViewState>(find.byType(ScoreView));
        final player = ScorePlayer(
          document: doc,
          controller: controller,
          view: vc,
        );
        try {
          player.play();
          player.speed = 4.0;
          var frames = 0;
          while (player.isPlaying && frames < 5000) {
            await tester.pump(const Duration(milliseconds: 100));
            frames++;
          }
          expect(player.isPlaying, isFalse, reason: name);
          expect(player.position, player.duration, reason: name);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            controller.highlightedCount,
            0,
            reason: '$name: nada deveria continuar aceso no fim',
          );
          final tl = player.timeline;
          expect(
            vc.displayedPage,
            tl.measures.last.view,
            reason: '$name: displayedPage no fim',
          );
        } finally {
          controller.clearAll();
          player.dispose();
          controller.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        expect(state.pictureStats.live, 0, reason: '$name: Picture vazando');
      });
    }
  });
}

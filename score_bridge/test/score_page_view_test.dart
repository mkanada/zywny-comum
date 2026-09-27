// `ScorePageView` (A01b): a segmentação não pode mudar um pixel.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  group('byte-identidade com o harness (critério 1)', () {
    final files = corpusFiles();
    if (files.isEmpty) {
      test('corpus ausente', () {
        markTestSkipped('$kCorpusDir não existe');
      }, skip: '$kCorpusDir não existe (gere com compare-corpus.sh)');
      return;
    }
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      testWidgets(name, (tester) async {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        for (var p = 0; p < doc.pages.length; p++) {
          final expected = await harnessBytes(tester, doc, p);
          final actual = await pageViewBytes(tester, doc, p);
          final diff = countDifferentPixels(expected, actual);
          expect(diff, 0, reason: '$name página ${p + 1}: $diff pixels');
          // Desmonta o widget antes da próxima página.
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  group('cache de Picture', () {
    late VsbDocument doc;
    setUp(() {
      doc = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
    });

    testWidgets('trocar cor não incrementa pictureBuilds (critério 2)', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      final page = doc.pages[0];
      final key = await pumpAtSize(
        tester,
        ScorePageView(document: doc, pageIndex: 0, controller: controller),
        page.widthPx,
        page.heightPx,
      );
      final state = tester.state<ScorePageViewState>(
        find.byType(ScorePageView),
      );
      final builds = state.pictureBuilds;
      expect(builds, greaterThan(0));
      final ids = animatableIdsFromTimemap(doc.timemap)
          .where(page.byId.containsKey)
          .take(5)
          .toList();
      expect(ids, isNotEmpty);
      for (final id in ids) {
        controller.setColor(id, const Color(0xFFFF0000));
        await tester.pump();
      }
      await captureBytes(tester, key, page.widthPx, page.heightPx);
      expect(state.pictureBuilds, builds);
      expect(state.layers.stats.live, builds);
    });

    testWidgets(
      'mudar de página descarta os Picture da anterior (critério 3)',
      (tester) async {
        final p0 = doc.pages[0];
        tester.view.physicalSize = Size(
          p0.widthPx.toDouble(),
          p0.heightPx.toDouble(),
        );
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Mesma estrutura de árvore nas montagens: o `State` é o mesmo.
        Widget at(int page) => Center(
          child: ScorePageView(document: doc, pageIndex: page),
        );
        await tester.pumpWidget(at(0));
        final state = tester.state<ScorePageViewState>(
          find.byType(ScorePageView),
        );
        final builds0 = state.pictureBuilds;
        expect(builds0, greaterThan(0));
        expect(state.pictureDisposals, 0);
        await tester.pumpWidget(at(1));
        expect(state.pictureDisposals, builds0);
        final builds1 = state.pictureBuilds;
        expect(builds1, greaterThan(builds0));
        expect(state.pictureStats.live, builds1 - builds0);
        // Voltar recompila: o cache da página 0 não ficou guardado.
        await tester.pumpWidget(at(0));
        expect(state.pictureBuilds, greaterThan(builds1));
        // Sair da árvore descarta tudo.
        final stats = state.pictureStats;
        await tester.pumpWidget(const SizedBox());
        expect(stats.live, 0);
      },
    );

    testWidgets('redimensionar não recompila', (tester) async {
      final page = doc.pages[0];
      await pumpAtSize(
        tester,
        ScorePageView(document: doc, pageIndex: 0),
        page.widthPx,
        page.heightPx,
      );
      final state = tester.state<ScorePageViewState>(
        find.byType(ScorePageView),
      );
      final builds = state.pictureBuilds;
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: page.widthPx / 2,
            child: ScorePageView(document: doc, pageIndex: 0),
          ),
        ),
      );
      await tester.pump();
      expect(state.pictureBuilds, builds);
    });
  });
}

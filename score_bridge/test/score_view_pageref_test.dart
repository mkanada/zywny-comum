// `ScoreView`/`ScorePageView` exibem um `PageRef`: páginas alternativas
// (§2.5, P03b). Usa `maple-leaf-rag.vsb` (regenerado em P03a com
// alternativas de P02c: 8 sequências).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  final doc = VsbDocument.fromBytes(
    File('test/fixtures/maple-leaf-rag.vsb').readAsBytesSync(),
  );

  Widget view(
    VsbDocument doc, {
    ScoreViewController? vc,
    ScoreController? controller,
    ValueChanged<int>? onPageChanged,
    ValueListenable<SweepCurtain?>? curtain,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: ScoreView(
      document: doc,
      controller: controller,
      viewController: vc,
      onPageChanged: onPageChanged,
      curtain: curtain,
    ),
  );

  test('critério 1 (pré-condição): a sequência 0 tem página 0 iniciando em '
      'seu próprio start', () {
    expect(doc.alternates, hasLength(8));
    final sequence = doc.alternates[0];
    expect(sequence.pages.first.firstMeasureId, sequence.start);
  });

  testWidgets('critério 1: showPage(PageRef(0, sequence: 0)) monta o '
      'ScorePageView certo e currentPage vira a página normal do compasso', (
    tester,
  ) async {
    final vc = ScoreViewController();
    final page0 = doc.pages[0];
    await pumpAtSize(tester, view(doc, vc: vc), page0.widthPx, page0.heightPx);

    final sequence = doc.alternates[0];
    final expectedNormalPage = doc.geometry.pageOf(sequence.start);
    expect(expectedNormalPage, isNotNull);

    vc.showPage(const PageRef(0, sequence: 0));
    await tester.pump();

    final pageView = tester.widget<ScorePageView>(find.byType(ScorePageView));
    expect(pageView.sequence, 0);
    expect(pageView.pageIndex, 0);
    expect(vc.currentPage, expectedNormalPage);
    expect(vc.displayedPage, const PageRef(0, sequence: 0));
  });

  testWidgets('critério 2: paridade de widget — página alternativa idêntica ao '
      'harness, pixel a pixel', (tester) async {
    final sequence = doc.alternates[0];
    final page = sequence.pages[0];

    final harness = await _harnessBytesFor(tester, doc, page);
    final vc = ScoreViewController();
    final key = await pumpAtSize(
      tester,
      view(doc, vc: vc),
      page.widthPx,
      page.heightPx,
    );
    vc.showPage(const PageRef(0, sequence: 0));
    await tester.pump();

    final widgetBytes = await captureBytes(
      tester,
      key,
      page.widthPx,
      page.heightPx,
    );

    final diff = countDifferentPixels(harness, widgetBytes);
    expect(diff, 0);
  });

  testWidgets(
    'critério 3: haste com targetSequence mostra a alternativa atrás; na '
    'conclusão displayedPage é a alternativa',
    (tester) async {
      final page0 = doc.pages[0];
      final curtainNotifier = ValueNotifier<SweepCurtain?>(null);
      final vc = ScoreViewController();
      await pumpAtSize(
        tester,
        view(doc, vc: vc, curtain: curtainNotifier),
        page0.widthPx,
        page0.heightPx,
      );

      final endX = sweepEndX(doc.pages[0], vc.barWidth);
      curtainNotifier.value = SweepCurtain(
        pageIndex: 0,
        edgeX: endX / 2,
        targetPageIndex: 0,
        targetSequence: 3,
      );
      await tester.pump();
      expect(find.byType(ScorePageView), findsNWidgets(2));

      curtainNotifier.value = SweepCurtain(
        pageIndex: 0,
        edgeX: endX,
        targetPageIndex: 0,
        targetSequence: 3,
      );
      await tester.pump();

      expect(vc.displayedPage, const PageRef(0, sequence: 3));
    },
  );

  testWidgets('critério 4: goToPage depois de uma alternativa volta às páginas '
      'normais', (tester) async {
    final page0 = doc.pages[0];
    final vc = ScoreViewController();
    await pumpAtSize(tester, view(doc, vc: vc), page0.widthPx, page0.heightPx);

    vc.showPage(const PageRef(0, sequence: 0));
    await tester.pump();
    expect(vc.displayedPage.isAlternate, isTrue);

    vc.goToPage(1);
    await tester.pump();
    expect(vc.displayedPage, const PageRef(1));
    expect(vc.currentPage, 1);
  });

  testWidgets('critério 5: destaque acende a nota na alternativa exibida', (
    tester,
  ) async {
    final sequence = doc.alternates[0];
    final page = sequence.pages[0];
    final noteId = 'm15xbieh'; // 1ª nota da página 0 da sequência 0
    final ref = doc.geometryOf(0).elementOf(noteId);
    expect(ref, isNotNull);

    final controller = ScoreController(document: doc);
    addTearDown(controller.dispose);
    final vc = ScoreViewController();
    final key = await pumpAtSize(
      tester,
      view(doc, vc: vc, controller: controller),
      page.widthPx,
      page.heightPx,
    );
    vc.showPage(const PageRef(0, sequence: 0));
    await tester.pump();

    controller.highlight(noteId);
    await tester.pump();

    final bytes = await captureBytes(tester, key, page.widthPx, page.heightPx);

    final rectPx = doc
        .geometryOf(0)
        .rectOf(ref!, pageWidth: page.widthPx.toDouble());
    final red = countRedPixels(bytes, page.widthPx, rectPx);
    expect(red, greaterThan(0));
    controller.clearAll();
  });

  testWidgets(
    'critério 6: sem sequence, PictureStats.live volta ao patamar depois de '
    'normal -> alternativa -> normal',
    (tester) async {
      final page0 = doc.pages[0];
      final vc = ScoreViewController();
      await pumpAtSize(
        tester,
        view(doc, vc: vc),
        page0.widthPx,
        page0.heightPx,
      );
      final state = tester.state<ScoreViewState>(find.byType(ScoreView));
      await tester.pump();
      final baseline = state.pictureStats.live;

      vc.showPage(const PageRef(0, sequence: 0));
      await tester.pump();
      vc.goToPage(0);
      await tester.pump();

      expect(state.pictureStats.live, baseline);
    },
  );
}

Future<ByteData> _harnessBytesFor(
  WidgetTester tester,
  VsbDocument doc,
  ScenePage page,
) async {
  final w = page.widthPx;
  final h = page.heightPx;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  ScenePainter(page, doc.glyphs).paint(canvas);
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(w, h)))!;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  picture.dispose();
  image.dispose();
  return bytes!;
}

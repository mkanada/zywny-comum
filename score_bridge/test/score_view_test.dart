// `ScoreView` (A03a/A03b/A03c): trilha de páginas, haste, rolagem contínua.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

/// Tempo para o `AnimationController` chegar ao fim e o widget assentar.
const _settle = Duration(seconds: 2);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  final nocturne = corpusDoc('Nocturne');
  if (nocturne == null) {
    test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
    return;
  }

  Widget view(
    VsbDocument doc, {
    ScoreViewController? vc,
    ScoreController? controller,
    ScorePageMode mode = ScorePageMode.pagedSweep,
    ValueChanged<int>? onPageChanged,
    ValueListenable<SweepCurtain?>? curtain,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: ScoreView(
      document: doc,
      controller: controller,
      viewController: vc,
      mode: mode,
      onPageChanged: onPageChanged,
      curtain: curtain,
    ),
  );

  Future<ScoreViewState> pumpScoreView(
    WidgetTester tester,
    VsbDocument doc,
    Widget widget, {
    int page = 0,
  }) async {
    await pumpAtSize(
      tester,
      widget,
      doc.pages[page].widthPx,
      doc.pages[page].heightPx,
    );
    return tester.state<ScoreViewState>(find.byType(ScoreView));
  }

  Future<ByteData> capture(WidgetTester tester, GlobalKey key, ScenePage p) =>
      captureBytes(tester, key, p.widthPx, p.heightPx);

  group('repouso pixel-idêntico (A03a, critério 1)', () {
    for (final file in corpusFiles()) {
      final name = file.uri.pathSegments.last;
      testWidgets('$name paginado', (tester) async {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        final vc = ScoreViewController();
        for (var p = 0; p < doc.pages.length; p++) {
          final page = doc.pages[p];
          final key = await pumpAtSize(
            tester,
            view(doc, vc: vc),
            page.widthPx,
            page.heightPx,
          );
          vc.goToPage(p);
          await tester.pump();
          expect(find.byType(ClipRect), findsNothing);
          final expected = await harnessBytes(tester, doc, p);
          final actual = await capture(tester, key, page);
          expect(
            countDifferentPixels(expected, actual),
            0,
            reason: '$name página ${p + 1}',
          );
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('$name contínuo', (tester) async {
        final doc = VsbDocument.fromBytes(file.readAsBytesSync());
        final vc = ScoreViewController();
        final page0 = doc.pages[0];
        final key = await pumpAtSize(
          tester,
          view(doc, vc: vc, mode: ScorePageMode.continuousScroll),
          page0.widthPx,
          page0.heightPx,
        );
        for (var p = 0; p < doc.pages.length; p++) {
          final page = doc.pages[p];
          if (page.widthPx != page0.widthPx ||
              page.heightPx != page0.heightPx) {
            continue; // a janela é do tamanho da primeira página
          }
          vc.goToPage(p);
          await tester.pump();
          await tester.pump();
          final expected = await harnessBytes(tester, doc, p);
          final actual = await capture(tester, key, page);
          expect(
            countDifferentPixels(expected, actual),
            0,
            reason: '$name página ${p + 1}',
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('navegação direta (A03a, critérios 2 e 3)', () {
    testWidgets('limites, saturação e onPageChanged', (tester) async {
      final doc = nocturne;
      final vc = ScoreViewController();
      final changes = <int>[];
      await pumpScoreView(
        tester,
        doc,
        view(doc, vc: vc, onPageChanged: changes.add),
      );
      final last = doc.pages.length - 1;
      expect(vc.currentPage, 0);
      expect(vc.goToPage(-3), 0);
      expect(changes, isEmpty, reason: 'não mudou de página');
      expect(vc.goToPage(999), last);
      expect(changes, [last]);
      expect(vc.nextPage(animate: false), last, reason: 'satura na última');
      expect(vc.goToPage(last), last);
      expect(changes, [last], reason: 'mesma página não dispara');
      expect(vc.previousPage(), last - 1);
      expect(vc.goToPage(0), 0);
      expect(vc.previousPage(), 0, reason: 'satura na primeira');
      expect(vc.nextPage(animate: false), 1);
      expect(changes, [last, last - 1, 0, 1]);
      await tester.pump();
      expect(vc.currentPage, 1);
    });

    testWidgets('7 páginas do início ao fim e de volta não vazam Picture', (
      tester,
    ) async {
      final doc = nocturne;
      expect(doc.pages.length, 7);
      final vc = ScoreViewController();
      final state = await pumpScoreView(tester, doc, view(doc, vc: vc));
      final stats = state.pictureStats;
      var maxLive = 0;
      final liveByPage = <int, int>{};
      Future<void> at(int p) async {
        vc.goToPage(p);
        await tester.pump();
        maxLive = maxLive > stats.live ? maxLive : stats.live;
        liveByPage[p] = stats.live;
      }

      for (var p = 0; p < 7; p++) {
        await at(p);
      }
      for (var p = 5; p >= 0; p--) {
        await at(p);
      }
      // Só a página corrente tem Picture vivo.
      final biggest = liveByPage.values.reduce((a, b) => a > b ? a : b);
      expect(maxLive, biggest);
      final builds = stats.builds;
      final disposals = stats.disposals;
      expect(builds - disposals, stats.live);
      // ignore: avoid_print
      print(
        'A03a leak: builds=$builds disposals=$disposals live=${stats.live} '
        'maxLive=$maxLive',
      );
      await tester.pumpWidget(const SizedBox());
      expect(stats.live, 0);
    });

    testWidgets('páginas de tamanhos diferentes: inteiras e centradas', (
      tester,
    ) async {
      final base = nocturne;
      ScenePage resized(ScenePage p, int w, int h) => ScenePage(
        index: p.index,
        width: p.width,
        height: p.height,
        contentHeight: p.contentHeight,
        viewBoxFactor: p.viewBoxFactor,
        viewBox: p.viewBox,
        baseWidth: p.baseWidth,
        baseHeight: p.baseHeight,
        userScaleX: p.userScaleX,
        userScaleY: p.userScaleY,
        widthPx: w,
        heightPx: h,
        fit: p.fit,
        origin: p.origin,
        root: p.root,
        elements: p.elements,
        byId: p.byId,
      );
      final doc = VsbDocument(
        manifest: base.manifest,
        glyphs: base.glyphs,
        pages: [
          resized(base.pages[0], 400, 600),
          resized(base.pages[1], 900, 500),
        ],
      );
      tester.view.physicalSize = const ui.Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vc = ScoreViewController();
      await tester.pumpWidget(view(doc, vc: vc));
      Rect r() => tester.getRect(find.byType(ScorePageView));
      // 400x600 cabe em 1000x800 (escala 1,333): 533x800, centrada.
      expect(r().center.dx, closeTo(500, 1e-6));
      expect(r().center.dy, closeTo(400, 1e-6));
      expect(r().height, closeTo(800, 1e-6));
      expect(r().width, closeTo(800 * 400 / 600, 1e-6));
      vc.goToPage(1);
      await tester.pump();
      expect(r().center.dx, closeTo(500, 1e-6));
      expect(r().center.dy, closeTo(400, 1e-6));
      expect(r().width, closeTo(1000, 1e-6));
      expect(r().height, closeTo(1000 * 500 / 900, 1e-6));
    });
  });

  group('haste (A03b)', () {
    late VsbDocument doc;
    setUp(() => doc = nocturne);

    ScenePage pageOf(int i) => doc.pages[i];
    double midX(int page) =>
        xFromPagePx(pageOf(page).widthPx / 2, pageOf(page));

    testWidgets('5 frames: repouso, entrada, estacionada, conclusão, repouso', (
      tester,
    ) async {
      final vc = ScoreViewController();
      await pumpScoreView(tester, doc, view(doc, vc: vc));
      final root = find.byType(ScoreView);
      // A caixa de captura é a do `pumpAtSize`.
      final boundaryKey =
          tester.widget<Center>(find.byType(Center).first).child!.key
              as GlobalKey;
      final a = pageOf(0);
      final aBytes = await harnessBytes(tester, doc, 0);
      final bBytes = await harnessBytes(tester, doc, 1);

      // (1) repouso de A
      expect(find.byType(ClipRect), findsNothing);
      var got = await capture(tester, boundaryKey, a);
      expect(countDifferentPixels(aBytes, got), 0);
      expect(root, findsOneWidget);

      // (3) haste estacionada no meio da página
      final edgeX = midX(0);
      unawaited(vc.sweepTo(edgeX, duration: const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // (2) meio da entrada
      expect(find.byType(ClipRect), findsOneWidget);
      final mid = await capture(tester, boundaryKey, a);
      await writePng(
        tester,
        mid,
        a.widthPx,
        a.heightPx,
        '../compare/out/a03b/frame2-entrada.png',
      );
      await tester.pump(const Duration(seconds: 1));
      got = await capture(tester, boundaryKey, a);
      await writePng(
        tester,
        got,
        a.widthPx,
        a.heightPx,
        '../compare/out/a03b/frame3-estacionada.png',
      );
      final edgePx = xToPagePx(edgeX, a).round();
      final barPx = (state(tester).barWidth * a.fit.scale).round();
      // Direita da haste: A. Esquerda dela: B. Em todos os sistemas (a
      // página inteira, de cima a baixo).
      var wrong = 0, wa = 0, wb = 0, wbar = 0;
      for (var y = 0; y < a.heightPx; y++) {
        for (var x = 0; x < a.widthPx; x++) {
          final g = pixelAt(got, a.widthPx, x, y);
          if (x >= edgePx + 1) {
            if (_far(g, pixelAt(aBytes, a.widthPx, x, y))) {
              wrong++;
              wa++;
            }
          } else if (x < edgePx - barPx - 1) {
            if (_far(g, pixelAt(bBytes, a.widthPx, x, y))) {
              wrong++;
              wb++;
            }
          } else if (x >= edgePx - barPx + 1 && x < edgePx - 1) {
            if (g != (0x15, 0x65, 0xC0)) {
              wrong++;
              wbar++;
            } // barColor, opaca
          }
        }
      }
      // ignore: avoid_print
      print('wrong=$wrong a=$wa b=$wb bar=$wbar edge=$edgePx bar=$barPx');
      expect(wrong, 0);
      // largura ≈ 2 notas: a cabeça de nota preta mede ~ barPx / 2.
      expect(barPx, greaterThan(10));

      // (4) meio da conclusão
      unawaited(vc.finishSweep(duration: const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final concl = await capture(tester, boundaryKey, a);
      await writePng(
        tester,
        concl,
        a.widthPx,
        a.heightPx,
        '../compare/out/a03b/frame4-conclusao.png',
      );
      await tester.pump(_settle);

      // (5) repouso de B, sem haste nem recorte
      expect(vc.currentPage, 1);
      expect(find.byType(ClipRect), findsNothing);
      got = await capture(tester, boundaryKey, pageOf(1));
      expect(countDifferentPixels(bBytes, got), 0);
      await writePng(
        tester,
        got,
        a.widthPx,
        a.heightPx,
        '../compare/out/a03b/frame5-repouso-b.png',
      );
      await writePng(
        tester,
        aBytes,
        a.widthPx,
        a.heightPx,
        '../compare/out/a03b/frame1-repouso-a.png',
      );
    });

    testWidgets('nextPage sem curtain externo varre inteiro em maxSweep', (
      tester,
    ) async {
      final vc = ScoreViewController();
      await pumpScoreView(tester, doc, view(doc, vc: vc));
      final changes = <int>[];
      vc.addListener(() => changes.add(vc.currentPage));
      expect(vc.nextPage(), 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ClipRect), findsOneWidget);
      expect(vc.currentPage, 0, reason: 'ainda varrendo A');
      await tester.pump(const Duration(seconds: 1));
      expect(vc.currentPage, 1);
      expect(changes, [1], reason: 'uma vez, não por frame');
      expect(find.byType(ClipRect), findsNothing);
    });

    testWidgets('interrupções: nextPage, goToPage e previousPage', (
      tester,
    ) async {
      final vc = ScoreViewController();
      await pumpScoreView(tester, doc, view(doc, vc: vc));
      void restOn(int page) {
        expect(vc.currentPage, page);
        expect(find.byType(ClipRect), findsNothing);
        expect(vc.isTurning, isFalse);
      }

      // nextPage durante a varredura: conclui.
      vc.nextPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(vc.isTurning, isTrue);
      vc.nextPage();
      await tester.pump();
      await tester.pump(_settle);
      restOn(1);

      // goToPage no meio: vai direto ao repouso do destino.
      vc.nextPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(vc.goToPage(4), 4);
      await tester.pump();
      restOn(4);
      await tester.pump(_settle);
      restOn(4);

      // previousPage logo depois: instantâneo.
      expect(vc.previousPage(), 3);
      await tester.pump();
      restOn(3);

      // Última página: nem haste nem exceção.
      vc.goToPage(6);
      await tester.pump();
      expect(vc.nextPage(), 6);
      await vc.sweepTo(10);
      await tester.pump(_settle);
      restOn(6);
    });

    testWidgets('curtain externo dirige a haste e a página corrente', (
      tester,
    ) async {
      final curtain = ValueNotifier<SweepCurtain?>(null);
      final vc = ScoreViewController();
      final pages = <int>[];
      final state = await pumpScoreView(
        tester,
        doc,
        view(doc, vc: vc, curtain: curtain, onPageChanged: pages.add),
      );
      final a = pageOf(0);
      expect(find.byType(ClipRect), findsNothing);
      curtain.value = SweepCurtain(pageIndex: 0, edgeX: midX(0));
      await tester.pump();
      expect(find.byType(ClipRect), findsOneWidget);
      // fora do intervalo aberto = repouso
      curtain.value = const SweepCurtain(pageIndex: 0, edgeX: 0);
      await tester.pump();
      expect(find.byType(ClipRect), findsNothing);
      curtain.value = SweepCurtain(pageIndex: 0, edgeX: midX(0));
      await tester.pump();
      // conclusão: a página seguinte vira a corrente
      curtain.value = SweepCurtain(
        pageIndex: 0,
        edgeX: sweepEndX(a, state.barWidth),
      );
      await tester.pump();
      expect(vc.currentPage, 1);
      expect(pages, [1]);
      curtain.value = null;
      await tester.pump();
      expect(find.byType(ClipRect), findsNothing);
      // seek para dentro de uma virada de outra página: A acompanha a curtain
      curtain.value = SweepCurtain(pageIndex: 3, edgeX: midX(3));
      await tester.pump();
      expect(vc.currentPage, 3);
      // última página: a curtain não desenha nada
      curtain.value = SweepCurtain(pageIndex: 6, edgeX: 100);
      await tester.pump();
      expect(find.byType(ClipRect), findsNothing);
    });

    group('página de destino (E03a)', () {
      testWidgets(
        'targetPageIndex: página revelada é o destino, não pageIndex+1 (critério 1)',
        (tester) async {
          final vc = ScoreViewController();
          await pumpScoreView(tester, doc, view(doc, vc: vc), page: 1);
          vc.goToPage(1);
          await tester.pump();
          final curtain = SweepCurtain(
            pageIndex: 1,
            edgeX: midX(1),
            targetPageIndex: 0,
          );
          await tester.pumpWidget(
            view(doc, vc: vc, curtain: ValueNotifier<SweepCurtain?>(curtain)),
          );
          await tester.pump();
          // A página A (1) está clipada à direita da haste; o destino (0),
          // sem clipe algum, é o fundo — visível à esquerda dela.
          final clippedPageView = tester.widget<ScorePageView>(
            find.descendant(
              of: find.byType(ClipRect),
              matching: find.byType(ScorePageView),
            ),
          );
          expect(clippedPageView.pageIndex, 1);
          final unclippedPageViews = tester
              .widgetList<ScorePageView>(find.byType(ScorePageView))
              .where(
                (w) => find
                    .ancestor(
                      of: find.byWidget(w),
                      matching: find.byType(ClipRect),
                    )
                    .evaluate()
                    .isEmpty,
              );
          expect(unclippedPageViews.map((w) => w.pageIndex), [0]);
        },
      );

      testWidgets(
        'última página só tem haste com destino explícito (critério 2)',
        (tester) async {
          final curtain = ValueNotifier<SweepCurtain?>(null);
          final vc = ScoreViewController();
          await pumpScoreView(tester, doc, view(doc, vc: vc, curtain: curtain));
          vc.goToPage(6);
          await tester.pump();
          // Sem destino: pageIndex + 1 (7) não existe, recusada.
          curtain.value = SweepCurtain(pageIndex: 6, edgeX: midX(6));
          await tester.pump();
          expect(find.byType(ClipRect), findsNothing);
          // Com destino explícito (a página anterior, por ex.): aceita.
          curtain.value = SweepCurtain(
            pageIndex: 6,
            edgeX: midX(6),
            targetPageIndex: 1,
          );
          await tester.pump();
          expect(find.byType(ClipRect), findsOneWidget);
        },
      );

      testWidgets('conclusão torna o destino a página corrente (critério 3)', (
        tester,
      ) async {
        final curtain = ValueNotifier<SweepCurtain?>(null);
        final vc = ScoreViewController();
        final pages = <int>[];
        await pumpScoreView(
          tester,
          doc,
          view(doc, vc: vc, curtain: curtain, onPageChanged: pages.add),
        );
        vc.goToPage(6);
        await tester.pump();
        pages.clear();
        curtain.value = SweepCurtain(
          pageIndex: 6,
          edgeX: sweepEndX(pageOf(6), defaultBarWidth(doc)),
          targetPageIndex: 1,
        );
        await tester.pump();
        expect(vc.currentPage, 1);
        expect(pages, [1]);
      });

      testWidgets(
        'salto para página não vizinha pinta as duas e não vaza Picture (critério 5)',
        (tester) async {
          expect(doc.pages.length, greaterThanOrEqualTo(7));
          final curtain = ValueNotifier<SweepCurtain?>(null);
          final vc = ScoreViewController();
          final state = await pumpScoreView(
            tester,
            doc,
            view(doc, vc: vc, curtain: curtain),
          );
          vc.goToPage(5);
          await tester.pump();
          curtain.value = SweepCurtain(
            pageIndex: 5,
            edgeX: midX(5),
            targetPageIndex: 0,
          );
          await tester.pump();
          expect(
            tester
                .widgetList<ScorePageView>(find.byType(ScorePageView))
                .map((w) => w.pageIndex)
                .toSet(),
            {5, 0},
          );
          // Conclusão: só a página 0 fica, sem vazar o Picture da 5.
          curtain.value = SweepCurtain(
            pageIndex: 5,
            edgeX: sweepEndX(pageOf(5), defaultBarWidth(doc)),
            targetPageIndex: 0,
          );
          await tester.pump();
          expect(vc.currentPage, 0);
          curtain.value = null;
          await tester.pump();
          await tester.pump();
          expect(
            tester
                .widgetList<ScorePageView>(find.byType(ScorePageView))
                .map((w) => w.pageIndex),
            [0],
          );
          await tester.pumpWidget(const SizedBox());
          expect(state.pictureStats.live, 0, reason: 'sem vazamento');
        },
      );
    });

    testWidgets('destaque atravessa a virada', (tester) async {
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      final vc = ScoreViewController();
      await pumpScoreView(
        tester,
        doc,
        view(doc, vc: vc, controller: controller),
      );
      final boundaryKey =
          tester.widget<Center>(find.byType(Center).first).child!.key
              as GlobalKey;
      final a = pageOf(0);
      final ids = animatableIdsFromTimemap(doc.timemap);
      String noteOn(int page, {bool rightOf = false, double? x}) {
        for (final e in pageOf(page).elements) {
          if (e.className != 'note' || !ids.contains(e.id)) continue;
          if (doc.geometry.elementOf(e.id) == null) continue;
          if (x != null && e.bbox.left <= x) continue;
          return e.id;
        }
        throw StateError('sem nota');
      }

      final edgeX = midX(0);
      final noteA = noteOn(0, x: edgeX + 100);
      final noteB = noteOn(1);
      controller.highlight(noteA, release: const Duration(seconds: 2));
      controller.release(noteA);
      await tester.pump();
      unawaited(vc.sweepTo(edgeX, duration: const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // B, já revelada à esquerda da haste, com uma nota acesa.
      final rectB = doc.geometry.rectForId(noteB)!;
      controller.highlight(noteB, hold: const Duration(seconds: 30));
      await tester.pump();
      final revealed = rectB.right < xToPagePx(edgeX, a) - 40;
      final frame = await capture(tester, boundaryKey, a);
      if (revealed) {
        expect(countRedPixels(frame, a.widthPx, rectB), greaterThan(0));
      }
      // Cor de A no meio do fade, antes e depois da conclusão.
      final c1 = controller.colorOf(noteA);
      expect(c1, isNotNull, reason: 'fade em curso');
      unawaited(vc.finishSweep(duration: const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final c2 = controller.colorOf(noteA);
      await tester.pump(const Duration(seconds: 1));
      expect(vc.currentPage, 1);
      final c3 = controller.colorOf(noteA);
      // O fade seguiu: verde/azul sobem em direção ao preto original? O
      // original é preto, o destaque é D32F2F: o canal vermelho desce.
      int red(ui.Color? c) => c == null ? 0 : (c.r * 255).round();
      expect(red(c2) <= red(c1), isTrue);
      expect(red(c3) <= red(c2), isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(
        controller.colorOf(noteA),
        isNull,
        reason: 'cor final = a original',
      );
      expect(controller.isHighlighted(noteA), isFalse);
      controller.clearAll();
    });
  });

  group('pagedSlide (A03b, item 5)', () {
    testWidgets('transição sem haste e repouso exato', (tester) async {
      final doc = nocturne;
      final vc = ScoreViewController();
      await pumpScoreView(
        tester,
        doc,
        view(doc, vc: vc, mode: ScorePageMode.pagedSlide),
      );
      expect(vc.nextPage(), 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(ScorePageView), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ScorePageView), findsOneWidget);
      expect(vc.currentPage, 1);
      expect(vc.previousPage(), 0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(vc.currentPage, 0);
      expect(find.byType(ScorePageView), findsOneWidget);
    });
  });

  group('contínuo e scrollToId (A03c)', () {
    testWidgets('rolagem mantém um número limitado de Picture', (tester) async {
      final doc = nocturne;
      final vc = ScoreViewController();
      final state = await pumpScoreView(
        tester,
        doc,
        view(doc, vc: vc, mode: ScorePageMode.continuousScroll),
      );
      final stats = state.pictureStats;
      var maxLive = 0;
      final animatable = animatableIdsFromTimemap(doc.timemap);
      final perPage = [
        for (final p in doc.pages)
          segmentPage(p, animatable).whereType<StaticSegment>().length,
      ];
      final bound = [...perPage]..sort();
      final limit = bound.reversed.take(3).reduce((a, b) => a + b);
      for (var p = 0; p < 7; p++) {
        vc.goToPage(p);
        await tester.pump();
        await tester.pump();
        maxLive = maxLive > stats.live ? maxLive : stats.live;
      }
      for (var p = 6; p >= 0; p--) {
        vc.goToPage(p);
        await tester.pump();
        await tester.pump();
        maxLive = maxLive > stats.live ? maxLive : stats.live;
      }
      // ignore: avoid_print
      print(
        'A03c: maxLive=$maxLive limite(3 páginas)=$limit builds='
        '${stats.builds} disposals=${stats.disposals}',
      );
      expect(maxLive, lessThanOrEqualTo(limit));
      await tester.pumpWidget(const SizedBox());
      expect(stats.live, 0, reason: 'sem vazamento');
    });

    for (final mode in [
      ScorePageMode.pagedSweep,
      ScorePageMode.continuousScroll,
    ]) {
      testWidgets('scrollToId deixa a bbox visível ($mode)', (tester) async {
        final doc = nocturne;
        final vc = ScoreViewController();
        final page0 = doc.pages[0];
        tester.view.physicalSize = ui.Size(
          page0.widthPx.toDouble(),
          page0.heightPx / 2,
        );
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(view(doc, vc: vc, mode: mode));
        await tester.pump();
        final lastPage = doc.pages.length - 1;
        final ref = doc.pages[lastPage].elements
            .map((e) => doc.geometry.elementOf(e.id))
            .whereType<ElementRef>()
            .firstWhere((r) => r.className == 'note');
        final sw = Stopwatch()..start();
        expect(vc.scrollToId(ref.id), isTrue);
        sw.stop();
        await tester.pump();
        await tester.pump();
        expect(vc.currentPage, lastPage);
        if (mode == ScorePageMode.continuousScroll) {
          final scroll = tester
              .widget<ListView>(find.byType(ListView))
              .controller!;
          final top = doc.pages
              .take(lastPage)
              .fold<double>(0, (s, p) => s + p.heightPx);
          final rect = doc.geometry.rectOf(ref);
          final y0 = top + rect.top - scroll.offset;
          final y1 = top + rect.bottom - scroll.offset;
          expect(y0, greaterThanOrEqualTo(-1));
          expect(y1, lessThanOrEqualTo(page0.heightPx / 2 + 1));
        }
        // ignore: avoid_print
        print('A03c scrollToId ($mode): ${sw.elapsedMicroseconds} µs');
        // Id expandido (E02a): resolve à base e rola para o mesmo lugar.
        vc.goToPage(0);
        await tester.pump();
        expect(vc.scrollToId('${ref.id}-rend2'), isTrue);
        await tester.pump();
        await tester.pump();
        expect(vc.currentPage, lastPage);
        // Id inexistente: false e sem mexer.
        final before = vc.currentPage;
        expect(vc.scrollToId('nao-existe-rend2'), isFalse);
        expect(vc.currentPage, before);
      });
    }
  });
}

ScoreViewState state(WidgetTester tester) =>
    tester.state<ScoreViewState>(find.byType(ScoreView));

/// Diferença de antialiasing tolerada durante a virada (a tolerância do
/// projeto: 128/255 por canal). O **repouso** continua exigindo 0 pixels.
bool _far((int, int, int) a, (int, int, int) b) =>
    (a.$1 - b.$1).abs() > 128 ||
    (a.$2 - b.$2).abs() > 128 ||
    (a.$3 - b.$3).abs() > 128;

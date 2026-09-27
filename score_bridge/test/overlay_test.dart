// Overlay de widgets, toque e `ScoreCursor` (A04b).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

const _red = Color(0xFFFF0000);

class _RectsPainter extends CustomPainter {
  _RectsPainter(this.rects);
  final List<Rect> rects;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final r in rects) {
      canvas.drawRect(r.deflate(1), paint);
    }
  }

  @override
  bool shouldRepaint(_RectsPainter old) => true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  final doc = corpusDoc('Nocturne');
  if (doc == null) {
    test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
    return;
  }
  final page = doc.pages[0];
  final rng = math.Random(11);

  List<ElementRef> notes(VsbDocument d, int n, {int pageIndex = 0}) {
    final all = [
      for (final e in d.pages[pageIndex].elements)
        if (e.className == 'note' && d.geometry.elementOf(e.id) != null)
          d.geometry.elementOf(e.id)!,
    ];
    return [for (var i = 0; i < n; i++) all[rng.nextInt(all.length)]];
  }

  testWidgets('custo zero sem overlayIds (critério 1)', (tester) async {
    await pumpAtSize(
      tester,
      ScorePageView(document: doc, pageIndex: 0),
      page.widthPx,
      page.heightPx,
    );
    final before = tester.allWidgets.length;
    await pumpAtSize(
      tester,
      ScorePageView(
        document: doc,
        pageIndex: 0,
        overlayBuilder: ScoreCursor.builder(),
      ),
      page.widthPx,
      page.heightPx,
    );
    expect(tester.allWidgets.length, before);
    // Com ids, a árvore cresce: um Positioned por id.
    final n = notes(doc, 3).map((r) => r.id).toSet();
    await pumpAtSize(
      tester,
      ScorePageView(
        document: doc,
        pageIndex: 0,
        overlayIds: n,
        overlayBuilder: ScoreCursor.builder(),
      ),
      page.widthPx,
      page.heightPx,
    );
    expect(find.byType(Positioned), findsNWidgets(n.length));
  });

  testWidgets('overlay coincide com retângulos do painter (critério 2)', (
    tester,
  ) async {
    final refs = notes(doc, 5);
    final ids = refs.map((r) => r.id).toSet();
    final rects = [
      for (final id in ids) doc.geometry.rectForId(id, pageWidth: 600)!,
    ];
    final w = 600;
    final h = (600 * page.heightPx / page.widthPx).round();
    final s = 600 / page.widthPx;
    ScorePageView base({Iterable<String> overlayIds = const []}) =>
        ScorePageView(
          document: doc,
          pageIndex: 0,
          overlayIds: overlayIds,
          overlayBuilder: ScoreCursor.builder(color: _red, thickness: 2),
        );
    Future<ByteData> render(Widget child) async {
      tester.view.physicalSize = ui.Size(w.toDouble(), h.toDouble());
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 600,
              height: 600 * page.heightPx / page.widthPx,
              child: child,
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1.0),
      ))!;
      return (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
    }

    final viaOverlay = await render(base(overlayIds: ids));
    final viaPainter = await render(
      CustomPaint(foregroundPainter: _RectsPainter(rects), child: base()),
    );
    var far = 0;
    for (var i = 0; i < viaOverlay.lengthInBytes; i += 4) {
      for (var c = 0; c < 3; c++) {
        if ((viaOverlay.getUint8(i + c) - viaPainter.getUint8(i + c)).abs() >
            128) {
          far++;
          break;
        }
      }
    }
    expect(far, 0, reason: 'escala $s');
    // Sanidade: as bordas de fato existem.
    expect(
      countRedPixels(viaOverlay, w, Rect.fromLTWH(0, 0, w * 1.0, h * 1.0)),
      greaterThan(50),
    );
  });

  testWidgets('onElementTap: id certo no centro, nada em área vazia '
      '(critério 3)', (tester) async {
    final taps = <String>[];
    await pumpAtSize(
      tester,
      ScorePageView(document: doc, pageIndex: 0, onElementTap: taps.add),
      page.widthPx,
      page.heightPx,
    );
    final origin = tester.getTopLeft(find.byType(ScorePageView));
    final chosen = notes(doc, 20);
    for (final ref in chosen) {
      taps.clear();
      final rect = doc.geometry.rectOf(ref);
      final expected = doc.geometry.idAt(0, rect.center, classes: {'note'});
      await tester.tapAt(origin + rect.center);
      expect(taps, [expected]);
      final got = doc.geometry.elementOf(taps.single)!;
      expect(got.className, 'note');
    }
    taps.clear();
    await tester.tapAt(origin + const Offset(2, 2));
    expect(taps, isEmpty);
  });

  testWidgets('alinhado após mudar a largura (critério 4)', (tester) async {
    final ref = notes(doc, 1).single;
    for (final w in [500.0, 900.0]) {
      tester.view.physicalSize = ui.Size(w, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: ScorePageView(
              document: doc,
              pageIndex: 0,
              overlayIds: [ref.id],
              overlayBuilder: ScoreCursor.builder(),
            ),
          ),
        ),
      );
      await tester.pump();
      final got = tester.getRect(find.byType(ScoreCursor));
      final want = doc.geometry.rectForId(ref.id, pageWidth: w)!;
      expect(got.left, closeTo(want.left, 1e-6));
      expect(got.top, closeTo(want.top, 1e-6));
      expect(got.width, closeTo(want.width, 1e-6));
      expect(got.height, closeTo(want.height, 1e-6));
    }
  });

  testWidgets('overlay é recortado com a página e a haste fica por cima '
      '(critério 4)', (tester) async {
    final vc = ScoreViewController();
    final edgeX = xFromPagePx(page.widthPx / 2, page);
    // Uma nota à esquerda da haste e outra à direita.
    final left = doc.pages[0].elements
        .map((e) => doc.geometry.elementOf(e.id))
        .whereType<ElementRef>()
        .firstWhere(
          (r) =>
              r.className == 'note' &&
              xToPagePx(r.bbox.right, page) < page.widthPx / 2 - 80,
        );
    final right = doc.pages[0].elements
        .map((e) => doc.geometry.elementOf(e.id))
        .whereType<ElementRef>()
        .firstWhere(
          (r) =>
              r.className == 'note' &&
              xToPagePx(r.bbox.left, page) > page.widthPx / 2 + 80,
        );
    final key = await pumpAtSize(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScoreView(
          document: doc,
          viewController: vc,
          overlayIds: [left.id, right.id],
          overlayBuilder: ScoreCursor.builder(
            color: _red,
            thickness: 3,
            fill: true,
            fillOpacity: 1,
          ),
        ),
      ),
      page.widthPx,
      page.heightPx,
    );
    unawaited(vc.sweepTo(edgeX, duration: const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final frame = await captureBytes(tester, key, page.widthPx, page.heightPx);
    final rectLeft = doc.geometry.rectOf(left);
    final rectRight = doc.geometry.rectOf(right);
    // À direita da haste o overlay (vermelho cheio) aparece.
    expect(countRedPixels(frame, page.widthPx, rectRight), greaterThan(20));
    // À esquerda, o overlay de A some junto com a página recortada (B está
    // ali, sem overlay, porque os ids são de A).
    expect(countRedPixels(frame, page.widthPx, rectLeft), 0);
  });

  for (final part in ['Nocturne', 'Scarlatti', 'Clair_de_Lune']) {
    testWidgets('ScoreCursor em $part (critério 5)', (tester) async {
      final d = corpusDoc(part)!;
      final ref = notes(d, 1).single;
      final p = d.pages[0];
      final key = await pumpAtSize(
        tester,
        ScorePageView(
          document: d,
          pageIndex: 0,
          overlayIds: [ref.id],
          overlayBuilder: ScoreCursor.builder(
            color: _red,
            thickness: 3,
            fill: true,
            fillOpacity: 0.25,
          ),
        ),
        p.widthPx,
        p.heightPx,
      );
      final frame = await captureBytes(tester, key, p.widthPx, p.heightPx);
      final rect = d.geometry.rectOf(ref);
      expect(countRedPixels(frame, p.widthPx, rect), greaterThan(5));
      await writePng(
        tester,
        frame,
        p.widthPx,
        p.heightPx,
        '../compare/out/a04b/cursor-$part.png',
      );
    });
  }
}

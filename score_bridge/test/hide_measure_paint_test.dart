// Compasso inteiro escondido (T17, regra 8): o contrato do controller
// (`setHiddenMeasures`, `revealMeasure`, `clearHidden`), a pausa de compasso do
// `StandInController.setMeasures` e a imagem: o compasso fica só com as linhas
// da pauta e a pausa de compasso na cor de repouso, e revelar devolve a página
// pixel a pixel.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'hide_paint_test.dart' show darkIn, diffIn, rectOfId, toPx;
import 'stand_in_layer_test.dart' show countColor;
import 'support/render_helpers.dart';

const _vsb = 'test/fixtures/sumico/h010.vsb';
const _rest = ui.Color(0xFF7B1FA2);
const _flash = ui.Color(0xFFD32F2F);
const _m = 'axzadr3'; // compasso comum no meio do sistema
const _next = 'r16x677f'; // outro compasso da página

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  late VsbDocument doc;
  late ScenePage page;

  setUp(() {
    doc = VsbDocument.fromBytes(File(_vsb).readAsBytesSync());
    page = doc.pages[0];
  });

  group('controller', () {
    test('measureIds: os compassos na ordem em que tocam', () {
      final ids = doc.measureIds;
      expect(ids, isNotEmpty);
      expect(ids.toSet().length, ids.length);
      expect(ids, contains(_m));
    });

    test(
      'setHiddenMeasures esconde notas, acordes e pausas; uma notificação',
      () {
        final controller = ScoreController(document: doc);
        addTearDown(controller.dispose);
        var n = 0;
        controller.addListener(() => n++);
        controller.setHiddenMeasures({_m});
        expect(n, 1);
        expect(controller.hiddenMeasureIds, {_m});
        expect(controller.isMeasureHidden(_m), isTrue);
        final shapes = doc.hiddenShapesForMeasures({_m});
        expect(controller.hiddenIds, shapes.notes.toSet());
        for (final id in shapes.notes) {
          expect(controller.isHidden(id), isTrue);
          expect(controller.colors[id], const ui.Color(0x00000000));
        }
        for (final id in shapes.chords) {
          expect(controller.colors[id], const ui.Color(0x00000000));
        }
        expect(controller.hiddenShapesOf(page).notes, shapes.notes);

        controller.setHiddenMeasures({_m});
        expect(n, 1, reason: 'igual não notifica');
        controller.revealMeasure(_next); // não está escondido
        expect(n, 1);
      },
    );

    test('revealMeasure e clearHidden devolvem tudo', () {
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      controller.setHiddenMeasures({_m, _next});
      final both = controller.hiddenIds.length;
      controller.revealMeasure(_next);
      expect(controller.hiddenMeasureIds, {_m});
      expect(controller.hiddenIds.length, lessThan(both));
      controller.clearHidden();
      expect(controller.hiddenMeasureIds, isEmpty);
      expect(controller.hiddenIds, isEmpty);
      expect(controller.colors, isEmpty);
    });

    test('nota solta e compasso convivem; o id expandido vale', () {
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      controller.setHidden({'r10709ff'});
      controller.setHiddenMeasures({'$_m-rend2'});
      expect(controller.hiddenMeasureIds, {_m});
      expect(controller.isHidden('r10709ff'), isTrue);
      controller.setHiddenMeasures({});
      expect(controller.hiddenIds, {'r10709ff'});
    });

    test('id que não é compasso é ignorado', () {
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);
      controller.setHiddenMeasures({'nao-existe'});
      expect(controller.hiddenMeasureIds, isEmpty);
    });

    test('a tercina some com o compasso (nó transparente)', () {
      final tri = VsbDocument.fromBytes(
        File('test/fixtures/sumico/g11-tercina.vsb').readAsBytesSync(),
      );
      final controller = ScoreController(document: tri);
      addTearDown(controller.dispose);
      controller.setHiddenMeasures({'fz4nyf'});
      final shapes = tri.hiddenShapesForMeasures({'fz4nyf'});
      expect(shapes.tuplets, isNotEmpty);
      for (final id in shapes.tuplets) {
        expect(controller.colors[id], const ui.Color(0x00000000));
      }
      expect(controller.hiddenLeavesOf(tri.pages[0]), isNotEmpty);
    });
  });

  group('pausa de compasso', () {
    late StandInController layer;
    var clock = Duration.zero;

    setUp(() {
      clock = Duration.zero;
      layer = StandInController(restColor: _rest)..nowOverride = () => clock;
      layer.attachDocument(doc);
    });
    tearDown(() => layer.dispose());

    test('uma pausa por pauta que tem nota, na cor de repouso', () {
      layer.setMeasures([_m]);
      expect(layer.keys, [_m]);
      final rests = layer.restsOf(_m);
      expect(rests, hasLength(2), reason: 'duas pautas, com nota');
      expect(rests.every((r) => r.glyphId.endsWith(':E4E3')), isTrue);
      expect(layer.visible, hasLength(2));
      expect(layer.visible.every((v) => v.color == _rest), isTrue);
      expect(layer.isEmpty, isFalse);
    });

    test('flash e remove valem para o compasso', () {
      layer.setMeasures([_m, _next]);
      layer.flash(_m, _flash, hold: const Duration(seconds: 1));
      expect(layer.colorOf(_m), _flash);
      expect(layer.colorOf(_next), _rest);
      layer.remove(_m);
      expect(layer.keys, [_next]);
      layer.setMeasures(const []);
      expect(layer.isEmpty, isTrue);
    });

    test('compasso que continua mantém o piscar', () {
      layer.setMeasures([_m, _next]);
      layer.flash(_m, _flash, hold: const Duration(seconds: 5));
      layer.setMeasures([_m]);
      expect(layer.colorOf(_m), _flash);
    });

    test('.vsb sem `inner` ou sem documento: sem pausa, sem erro', () {
      final bare = StandInController(restColor: _rest);
      addTearDown(bare.dispose);
      bare.setMeasures([_m]);
      expect(bare.visible, isEmpty);
      final old = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
      final onOld = StandInController(restColor: _rest)..attachDocument(old);
      addTearDown(onOld.dispose);
      onOld.setMeasures(['qualquer']);
      expect(onOld.visible, isEmpty);
    });
  });

  group('pintura', () {
    late int w;
    late int h;
    setUp(() {
      w = page.widthPx;
      h = page.heightPx;
    });

    testWidgets('o compasso fica só com a pauta e a pausa de compasso', (
      tester,
    ) async {
      final controller = ScoreController(document: doc);
      final layer = StandInController(restColor: _rest);
      addTearDown(controller.dispose);
      addTearDown(layer.dispose);
      final key = await pumpAtSize(
        tester,
        ScorePageView(
          document: doc,
          pageIndex: 0,
          controller: controller,
          standIns: layer,
        ),
        w,
        h,
      );
      final before = await captureBytes(tester, key, w, h);
      final area = rectOfId(doc, _m);

      controller.setHiddenMeasures({_m});
      layer.setMeasures([_m]);
      await tester.pump();
      final after = await captureBytes(tester, key, w, h);

      // Sobram as linhas da pauta e as barras: bem menos tinta que antes.
      final darkBefore = darkIn(before, w, area);
      final darkAfter = darkIn(after, w, area);
      expect(darkBefore, greaterThan(500));
      expect(darkAfter, lessThan(darkBefore ~/ 2));

      // A pausa de compasso (violeta) aparece, uma por pauta, no meio.
      for (final rest in layer.restsOf(_m)) {
        final box = doc.glyphs[rest.glyphId]!.bbox.toContourRect();
        final a = toPx(
          page,
          rest.x + box.left * rest.sx,
          rest.y + box.top * rest.sy,
        );
        final b = toPx(
          page,
          rest.x + box.right * rest.sx,
          rest.y + box.bottom * rest.sy,
        );
        expect(
          countColor(after, w, ui.Rect.fromPoints(a, b), _rest),
          greaterThan(40),
          reason: 'pausa de compasso em ${rest.staffId}',
        );
        expect(countColor(before, w, ui.Rect.fromPoints(a, b), _rest), 0);
      }

      // Um compasso vizinho não muda.
      final other = rectOfId(doc, _next);
      expect(diffIn(before, after, w, other.deflate(4)), 0);

      // Revelar tudo devolve a página pixel a pixel.
      controller.clearHidden();
      layer.clear();
      await tester.pump();
      final back = await captureBytes(tester, key, w, h);
      expect(
        diffIn(
          before,
          back,
          w,
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ),
        0,
      );
    });
  });
}

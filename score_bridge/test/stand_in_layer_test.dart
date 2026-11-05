// Camada da pausa substituta (L03): a cor de repouso, o piscar (ataque,
// sustentação, soltura), `remove` só da coluna dela, e a pintura nos pixels.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

const _vsb = 'test/fixtures/sumico/h010.vsb';
const _rest = ui.Color(0xFF7B1FA2); // violeta de repouso
const _flash = ui.Color(0xFFD32F2F);

// Colunas dos vetores (h010, página 0).
const _a = ['r10709ff', 'x1848jna', 'z1oagi0k']; // semínima, x 3446
const _b = ['qyrisol', 't1hslndl']; // colcheia, x 16765
const _dotted = ['g1qqc06o', 'y4ih5in']; // semínima pontuada, com ponto

/// Pixels de [bytes] (largura [w]) perto de [color] dentro de [rect].
int countColor(ByteData bytes, int w, ui.Rect rect, ui.Color color) {
  final data = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  var n = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * w + x) * 4;
      if ((data[i] - r).abs() < 40 &&
          (data[i + 1] - g).abs() < 40 &&
          (data[i + 2] - b).abs() < 40) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  late VsbDocument doc;
  late ScenePage page;
  late StandInController layer;
  var clock = Duration.zero;

  setUp(() {
    doc = VsbDocument.fromBytes(File(_vsb).readAsBytesSync());
    page = doc.pages[0];
    clock = Duration.zero;
    layer = StandInController(restColor: _rest)..nowOverride = () => clock;
    layer.attachDocument(doc);
  });

  tearDown(() => layer.dispose());

  /// O retângulo, em pixels da página, do glifo da pausa de [key].
  ui.Rect restRect(Object key) {
    final rest = layer.restOf(key)!;
    final box = doc.glyphs[rest.glyphId]!.bbox.toContourRect();
    final a = ui.Offset(
      (rest.x + box.left * rest.sx + page.origin.dx) * page.fit.scale +
          page.fit.tx,
      (rest.y + box.top * rest.sy + page.origin.dy) * page.fit.scale +
          page.fit.ty,
    );
    final b = ui.Offset(
      (rest.x + box.right * rest.sx + page.origin.dx) * page.fit.scale +
          page.fit.tx,
      (rest.y + box.bottom * rest.sy + page.origin.dy) * page.fit.scale +
          page.fit.ty,
    );
    return ui.Rect.fromPoints(a, b);
  }

  group('controller', () {
    test('setColumns calcula a pausa de cada coluna na cor de repouso', () {
      var notified = 0;
      layer.addListener(() => notified++);
      layer.setColumns({1: _a, 2: _b});
      expect(notified, 1);
      expect(layer.keys, [1, 2]);
      expect(layer.restOf(1)!.glyphId, endsWith(':E4E5'));
      expect(layer.restOf(2)!.glyphId, endsWith(':E4E6'));
      expect(layer.colorOf(1), _rest);
      expect(layer.visible.map((v) => v.key), [1, 2]);
      expect(layer.visible.every((v) => v.color == _rest), isTrue);
      expect(layer.isEmpty, isFalse);
    });

    test('coluna sem pausa calculável fica de fora, sem exceção', () {
      layer.setColumns({1: _a, 'ruim': const ['nao-existe']});
      expect(layer.keys, containsAll([1, 'ruim']));
      expect(layer.restOf('ruim'), isNull);
      expect(layer.visible.map((v) => v.key), [1]);
      layer.flash('ruim', _flash); // não explode
    });

    test('flash: cor do ataque, sustentação e soltura de volta ao repouso', () {
      layer.setColumns({1: _a, 2: _b});
      layer.flash(
        1,
        _flash,
        attack: const Duration(milliseconds: 100),
        hold: const Duration(milliseconds: 200),
        release: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      expect(layer.isFlashing, isTrue);
      expect(layer.colorOf(1), _rest, reason: 'começa no repouso');
      clock = const Duration(milliseconds: 50);
      expect(layer.colorOf(1), ui.Color.lerp(_rest, _flash, 0.5));
      clock = const Duration(milliseconds: 200);
      expect(layer.colorOf(1), _flash, reason: 'sustentação');
      clock = const Duration(milliseconds: 350);
      expect(layer.colorOf(1), ui.Color.lerp(_flash, _rest, 0.5));
      clock = const Duration(milliseconds: 500);
      expect(layer.colorOf(1), _rest, reason: 'voltou');
      // As outras colunas nunca saíram do repouso.
      expect(layer.colorOf(2), _rest);
      layer.tickForTest();
      expect(layer.isFlashing, isFalse);
    });

    test('flash sem parâmetros: instantâneo e some em 300 ms', () {
      layer.setColumns({1: _a});
      layer.flash(1, _flash);
      expect(layer.colorOf(1), _flash);
      clock = const Duration(milliseconds: 400);
      expect(layer.colorOf(1), _rest);
    });

    test('flash numa pausa piscando reinicia só a dela', () {
      layer.setColumns({1: _a, 2: _b});
      layer.flash(1, _flash, hold: const Duration(seconds: 1));
      clock = const Duration(milliseconds: 500);
      layer.flash(2, _flash, hold: const Duration(seconds: 1));
      clock = const Duration(milliseconds: 1200);
      expect(layer.colorOf(1), isNot(_flash), reason: 'já soltou');
      expect(layer.colorOf(2), _flash, reason: 'recomeçou em 500 ms');
    });

    test('setColumns mantém o piscar de quem continua e larga o de quem sai', () {
      layer.setColumns({1: _a, 2: _b});
      layer.flash(1, _flash, hold: const Duration(seconds: 5));
      layer.flash(2, _flash, hold: const Duration(seconds: 5));
      layer.setColumns({1: _a});
      expect(layer.colorOf(1), _flash);
      expect(layer.restOf(2), isNull);
      expect(layer.keys, [1]);
    });

    test('remove tira só aquela; clear tira todas', () {
      layer.setColumns({1: _a, 2: _b});
      layer.remove(1);
      expect(layer.keys, [2]);
      expect(layer.restOf(1), isNull);
      expect(layer.restOf(2), isNotNull);
      layer.remove(99); // sem efeito
      layer.clear();
      expect(layer.keys, isEmpty);
      expect(layer.isEmpty, isTrue);
    });

    test('outro documento refaz as pausas', () {
      layer.setColumns({1: _a});
      final other = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
      layer.attachDocument(other);
      expect(layer.keys, [1]);
      expect(layer.restOf(1), isNull, reason: 'os ids não são do outro .vsb');
    });

    test('sem documento: sem pausa; com `.vsb` antigo, nada quebra', () {
      final bare = StandInController(restColor: _rest);
      addTearDown(bare.dispose);
      bare.setColumns({1: _a});
      expect(bare.visible, isEmpty);

      final old = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
      final onOld = StandInController(restColor: _rest)..attachDocument(old);
      addTearDown(onOld.dispose);
      onOld.setColumns({1: const ['orw55dt']});
      expect(onOld.visible, isEmpty);
    });
  });

  group('pintura', () {
    Future<(GlobalKey, int, int)> mount(WidgetTester tester) async {
      final w = page.widthPx;
      final h = page.heightPx;
      final key = await pumpAtSize(
        tester,
        ScorePageView(document: doc, pageIndex: 0, standIns: layer),
        w,
        h,
      );
      return (key, w, h);
    }

    testWidgets('a pausa aparece na cor de repouso, no lugar da coluna', (
      tester,
    ) async {
      final (key, w, h) = await mount(tester);
      final bare = await captureBytes(tester, key, w, h);
      layer.setColumns({1: _a, 2: _b});
      await tester.pump();
      final shot = await captureBytes(tester, key, w, h);
      for (final k in [1, 2]) {
        expect(countColor(bare, w, restRect(k), _rest), 0);
        expect(
          countColor(shot, w, restRect(k), _rest),
          greaterThan(40),
          reason: 'pausa $k',
        );
      }
    });

    testWidgets('flash muda a cor da pausa e volta ao repouso (critério 4)', (
      tester,
    ) async {
      final (key, w, h) = await mount(tester);
      layer.setColumns({1: _a, 2: _b});
      await tester.pump();
      final rest = await captureBytes(tester, key, w, h);
      final rest1 = countColor(rest, w, restRect(1), _rest);
      expect(rest1, greaterThan(40));

      layer.flash(1, _flash, hold: const Duration(seconds: 1));
      await tester.pump();
      final flashing = await captureBytes(tester, key, w, h);
      expect(countColor(flashing, w, restRect(1), _flash), greaterThan(40));
      expect(countColor(flashing, w, restRect(1), _rest), 0);
      // A outra pausa continua no repouso.
      expect(
        countColor(flashing, w, restRect(2), _rest),
        countColor(rest, w, restRect(2), _rest),
      );

      clock = const Duration(seconds: 3);
      layer.tickForTest();
      await tester.pump();
      final back = await captureBytes(tester, key, w, h);
      expect(countColor(back, w, restRect(1), _flash), 0);
      expect(countColor(back, w, restRect(1), _rest), rest1);
    });

    testWidgets('remove apaga só aquela pausa (critério 4)', (tester) async {
      final (key, w, h) = await mount(tester);
      layer.setColumns({1: _a, 2: _b});
      await tester.pump();
      final both = await captureBytes(tester, key, w, h);
      final rect1 = restRect(1);
      final rect2 = restRect(2);
      final rest2 = countColor(both, w, rect2, _rest);
      expect(countColor(both, w, rect1, _rest), greaterThan(40));

      layer.remove(1);
      await tester.pump();
      final after = await captureBytes(tester, key, w, h);
      // A 2 ficou como estava; onde estava a 1, nenhum roxo.
      expect(countColor(after, w, rect2, _rest), rest2);
      expect(countColor(after, w, rect1, _rest), 0);
    });

    testWidgets('pausa pontuada: o ponto é um círculo na cor da pausa', (
      tester,
    ) async {
      final (key, w, h) = await mount(tester);
      layer.setColumns({1: _dotted});
      await tester.pump();
      final shot = await captureBytes(tester, key, w, h);
      final rest = layer.restOf(1)!;
      expect(rest.dots, hasLength(1));
      final dot = rest.dots.single;
      final c = ui.Offset(
        (dot.cx + page.origin.dx) * page.fit.scale + page.fit.tx,
        (dot.cy + page.origin.dy) * page.fit.scale + page.fit.ty,
      );
      final box = ui.Rect.fromCenter(center: c, width: 6, height: 6);
      expect(countColor(shot, w, box, _rest), greaterThan(15));
    });

    testWidgets('sem `standIns` a árvore não ganha camada nenhuma', (
      tester,
    ) async {
      await pumpAtSize(
        tester,
        ScorePageView(document: doc, pageIndex: 0),
        page.widthPx,
        page.heightPx,
      );
      expect(find.byType(IgnorePointer), findsNothing);
    });
  });
}

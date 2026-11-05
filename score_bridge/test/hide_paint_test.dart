// Nota escondida (L02): o que o controller e o `ScorePageView` fazem com o
// cálculo de hide.dart — nota, acorde, barra de ligação e linha suplementar
// somem da imagem; revelar e `clearHidden` devolvem a página pixel a pixel;
// destaque e toque não enxergam a nota escondida; e as recompilações de
// `Picture` estão nas formas sem id, não nas notas.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

const _vsb = 'test/fixtures/sumico/h010.vsb';

/// Pixels `(x, y)` da página (largura natural, dpr 1) de um ponto do
/// referencial de conteúdo.
ui.Offset toPx(ScenePage page, double x, double y) => ui.Offset(
  (x + page.origin.dx) * page.fit.scale + page.fit.tx,
  (y + page.origin.dy) * page.fit.scale + page.fit.ty,
);

/// Quantos pixels escuros (preto da partitura) há em [rect] da imagem [w] de
/// largura.
int darkIn(ByteData bytes, int w, ui.Rect rect) {
  final data = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var n = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * w + x) * 4;
      if (data[i] < 110 && data[i + 1] < 110 && data[i + 2] < 110) {
        n++;
      }
    }
  }
  return n;
}

/// Pixels diferentes entre [a] e [b] dentro de [rect].
int diffIn(ByteData a, ByteData b, int w, ui.Rect rect) {
  var n = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * w + x) * 4;
      if (a.getUint32(i) != b.getUint32(i)) {
        n++;
      }
    }
  }
  return n;
}

/// Retângulo, em pixels da página, de um nó da cena por id.
ui.Rect rectOfId(VsbDocument doc, String id) =>
    doc.geometry.rectForId(id, pageWidth: doc.pages[0].widthPx.toDouble())!;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  late VsbDocument doc;
  late ScenePage page;
  late int w;
  late int h;

  setUp(() {
    doc = VsbDocument.fromBytes(File(_vsb).readAsBytesSync());
    page = doc.pages[0];
    w = page.widthPx;
    h = page.heightPx;
  });

  Future<(GlobalKey, ScorePageViewState)> mount(
    WidgetTester tester,
    ScoreController controller, {
    void Function(String id)? onTap,
  }) async {
    final key = await pumpAtSize(
      tester,
      ScorePageView(
        document: doc,
        pageIndex: 0,
        controller: controller,
        onElementTap: onTap,
      ),
      w,
      h,
    );
    return (key, tester.state<ScorePageViewState>(find.byType(ScorePageView)));
  }

  testWidgets('esconder uma nota fora de barra: nada dela fica (critério 2)', (
    tester,
  ) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final before = await captureBytes(tester, key, w, h);

    // `r10709ff`: soprano solta (sem barra), cabeça + haste.
    final rect = rectOfId(doc, 'r10709ff').inflate(2);
    final head = rectOfId(doc, 'r10709ff');
    final headBox = ui.Rect.fromLTWH(head.left, head.bottom - 20, head.width, 20);
    final darkBefore = darkIn(before, w, headBox);
    expect(darkBefore, greaterThan(100), reason: 'a cabeça existe antes');

    controller.setHidden({'r10709ff'});
    await tester.pump();
    final after = await captureBytes(tester, key, w, h);

    // A cabeça sumiu (sobra no máximo a linha da pauta que a cruza).
    expect(darkIn(after, w, headBox), lessThan(darkBefore ~/ 5));
    // A haste sumiu: o retângulo da nota tem menos tinta.
    expect(
      darkIn(after, w, rect),
      lessThan(darkIn(before, w, rect) ~/ 2),
    );
    // E nada mudou fora da nota (a coluna dela não tem acorde, barra nem
    // traço): toda diferença está dentro da bbox dela.
    final total = countDifferentPixels(before, after);
    expect(total, greaterThan(0));
    expect(
      diffIn(before, after, w, rect),
      total,
      reason: 'só a nota escondida muda',
    );
  });

  testWidgets('a letra da nota escondida continua (verse)', (tester) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final before = await captureBytes(tester, key, w, h);

    // `qyrisol` tem a sílaba `r18zfxs7` (verse) como filha.
    final verse = rectOfId(doc, 'r18zfxs7');
    expect(darkIn(before, w, verse), greaterThan(50));

    controller.setHidden({'qyrisol'});
    await tester.pump();
    final after = await captureBytes(tester, key, w, h);
    expect(diffIn(before, after, w, verse), 0, reason: 'a letra não muda');
    expect(countDifferentPixels(before, after), greaterThan(0));
  });

  testWidgets('acorde: haste e colchete saem com as duas notas (regra 1)', (
    tester,
  ) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final before = await captureBytes(tester, key, w, h);

    // `yy2zfkq`: alto e tenor em acorde de mínimas; a haste é do acorde.
    // Só o trecho abaixo da cabeça mais baixa (a do tenor, `x1848jna`): ali só
    // há haste.
    final stemFull = rectOfId(doc, 'ifmafny');
    final tenor = rectOfId(doc, 'x1848jna');
    final stem = ui.Rect.fromLTRB(
      stemFull.left,
      tenor.bottom + 2,
      stemFull.right,
      stemFull.bottom,
    );
    final stemBefore = darkIn(before, w, stem);
    expect(stemBefore, greaterThan(20));

    // Só uma das duas notas: o acorde fica, a haste fica.
    controller.setHidden({'x1848jna'});
    await tester.pump();
    final half = await captureBytes(tester, key, w, h);
    expect(darkIn(half, w, stem), stemBefore);

    // As duas: o acorde some inteiro, com a haste.
    controller.setHidden({'x1848jna', 'z1oagi0k'});
    await tester.pump();
    final both = await captureBytes(tester, key, w, h);
    expect(darkIn(both, w, stem), lessThan(stemBefore ~/ 4));

    // Revelar uma: a haste volta.
    controller.reveal('x1848jna');
    await tester.pump();
    final back = await captureBytes(tester, key, w, h);
    expect(darkIn(back, w, stem), stemBefore);
  });

  testWidgets('barra de ligação: 1 de 2 fica, 2 de 2 some, revelar volta '
      '(critério 3)', (tester) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final index = HidePageIndex.of(doc, page);
    final beam = index.beams.firstWhere((b) => b.id == 'l1z05zi4');
    expect(beam.noteIds, containsAll(['m1ujlm1s', 'nc27kmr']));
    // A caixa da barra: os vértices do contorno da primeira forma.
    final path = beam.shapes.first as ScenePath;
    final v = path.paths.first.v;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < v.length; i += 2) {
      minX = minX < v[i] ? minX : v[i];
      maxX = maxX > v[i] ? maxX : v[i];
      minY = minY < v[i + 1] ? minY : v[i + 1];
      maxY = maxY > v[i + 1] ? maxY : v[i + 1];
    }
    final a = toPx(page, minX, minY);
    final b = toPx(page, maxX, maxY);
    // Só o miolo entre as hastes (as notas e as hastes não entram na conta).
    final box = ui.Rect.fromPoints(a, b).deflate(0).intersect(
      ui.Rect.fromLTRB(
        a.dx + (b.dx - a.dx) * 0.3,
        a.dy,
        b.dx - (b.dx - a.dx) * 0.3,
        b.dy,
      ),
    );
    final before = await captureBytes(tester, key, w, h);
    final beamInk = darkIn(before, w, box);
    expect(beamInk, greaterThan(10), reason: 'a barra existe antes');

    // 1 de 2 (a primeira coluna): a barra fica.
    controller.setHidden({'m1ujlm1s', 'u1knnyxl', 'w1x5tsbc'});
    await tester.pump();
    final one = await captureBytes(tester, key, w, h);
    expect(darkIn(one, w, box), beamInk);

    // 2 de 2: a barra some.
    controller.setHidden({'m1ujlm1s', 'u1knnyxl', 'w1x5tsbc', 'nc27kmr'});
    await tester.pump();
    final two = await captureBytes(tester, key, w, h);
    expect(darkIn(two, w, box), lessThan(beamInk ~/ 3));

    // Revelar uma: a barra volta, igual ao estado de antes.
    controller.reveal('nc27kmr');
    await tester.pump();
    final back = await captureBytes(tester, key, w, h);
    expect(countDifferentPixels(one, back), 0);
  });

  testWidgets('linha suplementar: só o traço da coluna escondida some '
      '(critério 4)', (tester) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final index = HidePageIndex.of(doc, page);
    final hidden = {'qyrisol', 't1hslndl'};
    final mine = index.ledgers.firstWhere(
      (l) =>
          l.staffId == 'a1vokjmm' &&
          !l.above &&
          l.k == 1 &&
          (l.x1 - 16717).abs() < 1,
    );
    final neighbours = [
      for (final l in index.ledgers)
        if (!l.hiddenBy(hidden) && l.staffId == 'a1vokjmm' && !l.above) l,
    ];
    expect(neighbours, isNotEmpty);

    ui.Rect dash(HideLedger l) {
      final y = (l.shape as ScenePath).paths.first.v[1];
      final a = toPx(page, l.x1, y);
      final b = toPx(page, l.x2, y);
      return ui.Rect.fromLTRB(a.dx, a.dy - 1, b.dx, a.dy + 1);
    }

    final before = await captureBytes(tester, key, w, h);
    final mineInk = darkIn(before, w, dash(mine));
    expect(mineInk, greaterThan(10));

    controller.setHidden(hidden);
    await tester.pump();
    final after = await captureBytes(tester, key, w, h);

    // O dela sumiu (a cabeça escondida também estava em cima dele).
    expect(darkIn(after, w, dash(mine)), lessThan(mineInk ~/ 4));
    // Os das colunas vizinhas ficam como estavam.
    for (final n in neighbours) {
      expect(
        diffIn(before, after, w, dash(n)),
        0,
        reason: 'traço vizinho x ${n.x1}-${n.x2}',
      );
    }
  });

  testWidgets('clearHidden devolve a página pixel a pixel (critério 5)', (
    tester,
  ) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final before = await captureBytes(tester, key, w, h);

    // Notas soltas, acordes, barra e traço de uma vez.
    controller.setHidden({
      'm1ujlm1s', 'u1knnyxl', 'w1x5tsbc', 'nc27kmr', // barra + traço + acorde
      'r10709ff', 'x1848jna', 'z1oagi0k', // acorde + traço
      'qyrisol', 't1hslndl',
    });
    await tester.pump();
    final hiddenImg = await captureBytes(tester, key, w, h);
    expect(countDifferentPixels(before, hiddenImg), greaterThan(0));

    controller.clearHidden();
    await tester.pump();
    final after = await captureBytes(tester, key, w, h);
    expect(countDifferentPixels(before, after), 0);
    expect(controller.hiddenIds, isEmpty);
    expect(controller.colors, isEmpty);
  });

  testWidgets('50 notas escondidas e rereveladas uma a uma: as recompilações '
      'estão nas formas sem id (critério 6)', (tester) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, state) = await mount(tester, controller);
    await captureBytes(tester, key, w, h);

    final index = HidePageIndex.of(doc, page);
    // 50 notas seguidas da página, na ordem do timemap (colunas inteiras).
    final ids = <String>[
      for (final e in doc.timemap!)
        for (final id in e.on)
          if (index.noteIds.contains(id)) id,
    ].take(50).toList();
    expect(ids.length, 50);

    final b0 = state.pictureBuilds;
    expect(b0, state.layers.segments.staticSegmentCount);

    controller.setHidden(ids.toSet());
    await tester.pump();
    await captureBytes(tester, key, w, h);
    final bHide = state.pictureBuilds;
    // Uma só geração nova, mesmo escondendo 50 notas, acordes, barras e traços.
    final hideGeneration = state.layers.segments.staticSegmentCount;
    expect(bHide - b0, hideGeneration, reason: 'esconder 50: uma recompilação');

    // Revelar uma a uma: só recompila quando a barra ou o traço volta.
    var rebuilds = 0;
    var expectedRebuilds = 0;
    var current = controller.hiddenLeavesOf(page);
    for (final id in ids) {
      final layers = state.layers;
      final builds = state.pictureBuilds;
      controller.reveal(id);
      await tester.pump();
      await captureBytes(tester, key, w, h);
      final next = controller.hiddenLeavesOf(page);
      final leavesChanged = next.length != current.length;
      current = next;
      final rebuilt = !identical(layers, state.layers);
      expect(rebuilt, leavesChanged, reason: 'revelar $id');
      if (leavesChanged) expectedRebuilds++;
      if (rebuilt) {
        rebuilds++;
        expect(
          state.pictureBuilds - builds,
          state.layers.segments.staticSegmentCount,
        );
      } else {
        expect(state.pictureBuilds, builds, reason: 'revelar $id: sem Picture');
      }
    }
    expect(rebuilds, expectedRebuilds);
    expect(controller.hiddenIds, isEmpty);
    // Para o registro do passo (notas de execução).
    // ignore: avoid_print
    print(
      'L02 critério 6: $b0 Picture na 1ª geração; esconder 50 notas = 1 geração '
      '(${bHide - b0} Picture); revelar ${ids.length} uma a uma = $rebuilds '
      'gerações (${state.pictureBuilds - bHide} Picture); gravação total '
      '${state.pictureStats.buildMicroseconds ~/ 1000} ms em '
      '${state.pictureBuilds} Picture',
    );
  });

  testWidgets('highlight em nota escondida não a mostra; depois de reveal, '
      'mostra (critério 7)', (tester) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final (key, _) = await mount(tester, controller);
    final head = rectOfId(doc, 'r10709ff');

    controller.setHidden({'r10709ff'});
    await tester.pump();
    controller.highlight('r10709ff', hold: const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.haloColors, isEmpty, reason: 'sem halo');
    final hiddenShot = await captureBytes(tester, key, w, h);
    expect(countRedPixels(hiddenShot, w, head), 0);

    controller.reveal('r10709ff');
    await tester.pump();
    controller.highlight('r10709ff', hold: const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 50));
    final shown = await captureBytes(tester, key, w, h);
    expect(countRedPixels(shown, w, head), greaterThan(50));
    controller.clearAll();
  });

  testWidgets('nota escondida não responde a toque; revelada, responde', (
    tester,
  ) async {
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final tapped = <String>[];
    await mount(tester, controller, onTap: tapped.add);
    final head = rectOfId(doc, 'r10709ff');
    final origin = tester.getTopLeft(find.byType(ScorePageView));
    final at = origin + ui.Offset(head.center.dx, head.bottom - 8);

    controller.setHidden({'r10709ff'});
    await tester.pump();
    await tester.tapAt(at);
    await tester.pump();
    expect(tapped, isEmpty);

    controller.reveal('r10709ff');
    await tester.pump();
    await tester.tapAt(at);
    await tester.pump();
    expect(tapped, ['r10709ff']);
  });
}

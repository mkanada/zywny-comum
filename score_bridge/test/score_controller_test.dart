// `ScoreController` (A01c cor instantânea, A02b destaques): renderiza de
// verdade e compara pixels contra o repouso.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/colored_fixture.dart';
import 'support/render_helpers.dart';

const _red = Color(0xFFFF0000);

/// Caixa (em pixels do widget, sem escala extra) de um nó, inflada [pad].
ui.Rect _pixelBox(ScenePage page, SceneNode node, {double pad = 3}) {
  final b = node.bbox!;
  final f = page.fit;
  return ui.Rect.fromLTRB(
    f.tx + (b.left + page.origin.dx) * f.scale,
    f.ty + (b.top + page.origin.dy) * f.scale,
    f.tx + (b.right + page.origin.dx) * f.scale,
    f.ty + (b.bottom + page.origin.dy) * f.scale,
  ).inflate(pad);
}

/// Retângulo mínimo dos pixels diferentes, ou `null` se não há nenhum.
ui.Rect? _diffBounds(ByteData a, ByteData b, int width) {
  final ra = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
  final rb = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
  int? minX, minY, maxX, maxY;
  for (var i = 0; i < ra.length; i += 4) {
    if (ra[i] != rb[i] ||
        ra[i + 1] != rb[i + 1] ||
        ra[i + 2] != rb[i + 2] ||
        ra[i + 3] != rb[i + 3]) {
      final p = i ~/ 4;
      final x = p % width;
      final y = p ~/ width;
      minX = minX == null || x < minX ? x : minX;
      maxX = maxX == null || x > maxX ? x : maxX;
      minY = minY == null || y < minY ? y : minY;
      maxY = maxY == null || y > maxY ? y : maxY;
    }
  }
  if (minX == null) {
    return null;
  }
  return ui.Rect.fromLTRB(
    minX.toDouble(),
    minY!.toDouble(),
    maxX! + 1.0,
    maxY! + 1.0,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  late VsbDocument doc;
  late ScenePage page;
  late List<String> noteIds; // notas da página 0, no timemap, com haste

  setUp(() {
    doc = loadSatie();
    page = doc.pages[0];
    noteIds = [for (final n in notesWithStem(doc, 0)) n.id!];
  });

  Future<ScorePageViewState> mount(
    WidgetTester tester,
    VsbDocument d,
    ScoreController? controller, {
    Set<String>? animatableIds,
  }) async {
    final p = d.pages[0];
    tester.view.physicalSize = Size(
      p.widthPx.toDouble(),
      p.heightPx.toDouble(),
    );
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: _key,
          child: ScorePageView(
            document: d,
            pageIndex: 0,
            controller: controller,
            animatableIds: animatableIds,
          ),
        ),
      ),
    );
    return tester.state<ScorePageViewState>(find.byType(ScorePageView));
  }

  Future<ByteData> shot(WidgetTester tester, VsbDocument d) =>
      captureBytes(tester, _key, d.pages[0].widthPx, d.pages[0].heightPx);

  group('cor instantânea (A01c)', () {
    testWidgets('setColor recolore toda a subárvore da nota e só ela', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      final rest = await shot(tester, doc);

      final node = notesWithStem(doc, 0).first;
      controller.setColor(node.id!, _red);
      await tester.pump();
      final painted = await shot(tester, doc);

      final bounds = _diffBounds(rest, painted, page.widthPx)!;
      final box = _pixelBox(page, node);
      // Nenhum pixel mudou fora da caixa da nota...
      expect(box.contains(bounds.topLeft), isTrue, reason: '$bounds ⊄ $box');
      expect(
        box.contains(bounds.bottomRight),
        isTrue,
        reason: '$bounds ⊄ $box',
      );
      // ...e a mudança cobre a cabeça **e** a haste (quase toda a altura).
      expect(
        bounds.height,
        greaterThan(0.8 * node.bbox!.height * page.fit.scale),
      );
      // Tudo o que mudou ficou avermelhado (R > B em todo pixel diferente).
      var changed = 0;
      for (var i = 0; i < rest.lengthInBytes; i += 4) {
        if (rest.getUint32(i) != painted.getUint32(i)) {
          changed++;
          expect(painted.getUint8(i), greaterThan(painted.getUint8(i + 2)));
        }
      }
      expect(changed, greaterThan(50));
    });

    testWidgets('clearColor devolve o repouso byte a byte, também com @color', (
      tester,
    ) async {
      // Repouso sem cor.
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      final rest = await shot(tester, doc);
      controller.setColors({for (final id in noteIds.take(10)) id: _red});
      await tester.pump();
      expect(
        countDifferentPixels(rest, await shot(tester, doc)),
        greaterThan(0),
      );
      for (final id in noteIds.take(10)) {
        controller.clearColor(id);
      }
      await tester.pump();
      expect(countDifferentPixels(rest, await shot(tester, doc)), 0);

      // Repouso com uma nota azul vinda do documento (`@color`).
      final blueId = noteIds[3];
      final blueDoc = loadSatieWithColors({blueId: '#0000ff'});
      final c2 = ScoreController();
      addTearDown(c2.dispose);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, blueDoc, c2);
      final blueRest = await shot(tester, blueDoc);
      expect(countDifferentPixels(rest, blueRest), greaterThan(0));
      c2.setColor(blueId, _red);
      await tester.pump();
      expect(
        countDifferentPixels(blueRest, await shot(tester, blueDoc)),
        greaterThan(0),
      );
      c2.clearColor(blueId);
      await tester.pump();
      // Voltou ao AZUL, não ao preto.
      expect(countDifferentPixels(blueRest, await shot(tester, blueDoc)), 0);
    });

    test('setColors com 64 ids notifica uma vez só', () {
      final controller = ScoreController(document: doc);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final ids = animatableIdsFromTimemap(doc.timemap)
          .where(page.byId.containsKey)
          .take(64)
          .toList();
      expect(ids, hasLength(64));
      controller.setColors({for (final id in ids) id: _red});
      expect(notifications, 1);
      controller.setColors({for (final id in ids) id: _red}); // nada mudou
      expect(notifications, 1);
      controller.clearAll();
      expect(notifications, 2);
      controller.dispose();
    });

    testWidgets('nenhuma operação de cor recompila Picture', (tester) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      final state = await mount(tester, doc, controller);
      final builds = state.pictureBuilds;
      controller.setColors({for (final id in noteIds.take(64)) id: _red});
      await tester.pump();
      await shot(tester, doc);
      controller.setColor(noteIds[0], const Color(0xFF00FF00));
      controller.clearColor(noteIds[1]);
      await tester.pump();
      controller.clearAll();
      await tester.pump();
      expect(state.pictureBuilds, builds);
    });

    testWidgets('id não-animável é promovido a dinâmico (recompila uma vez)', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      // Nenhum id animável: a página inteira é um só Picture estático.
      final state = await mount(tester, doc, controller, animatableIds: {});
      expect(state.layers.segments, hasLength(1));
      final rest = await shot(tester, doc);
      final builds = state.pictureBuilds;
      expect(builds, 1);

      controller.setColor(noteIds.first, _red);
      await tester.pump();
      final painted = await shot(tester, doc);
      expect(countDifferentPixels(rest, painted), greaterThan(0));
      expect(state.pictureBuilds, greaterThan(builds));
      final afterPromotion = state.pictureBuilds;
      // Trocar de novo a cor do mesmo id já não recompila.
      controller.setColor(noteIds.first, const Color(0xFF00FF00));
      await tester.pump();
      await shot(tester, doc);
      expect(state.pictureBuilds, afterPromotion);
      // O Picture antigo foi descartado.
      expect(state.pictureStats.live, state.layers.compiledCount);
      // E voltar ao repouso continua exato.
      controller.clearAll();
      await tester.pump();
      expect(countDifferentPixels(rest, await shot(tester, doc)), 0);
    });

    testWidgets('id que não existe na página/documento é ignorado', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      final state = await mount(tester, doc, controller);
      final rest = await shot(tester, doc);
      final builds = state.pictureBuilds;
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setColor('nao-existe-rend2', _red);
      controller.highlight('nao-existe-rend2');
      expect(notifications, 0);
      expect(controller.colorOf('nao-existe-rend2'), isNull);
      expect(controller.tickerActive, isFalse);
      await tester.pump();
      expect(countDifferentPixels(rest, await shot(tester, doc)), 0);
      expect(state.pictureBuilds, builds);
    });
  });

  group('destaques (A02b)', () {
    testWidgets(
      'highlightAll com 50 ids: uma notificação; -rend2 resolve à base (E02a)',
      (tester) async {
        final controller = ScoreController();
        addTearDown(controller.dispose);
        await mount(tester, doc, controller);
        final real = noteIds.take(50).toList();
        expect(real, hasLength(50));
        // A mistura exata do plano: ids reais + ids `-rend2` (só no
        // timemap) das mesmas notas — antes de E02a, `_known` rejeitava os
        // `-rend2` em silêncio; agora `sceneIdOf` os resolve à mesma nota
        // real, então eles não acrescentam nada a `highlightedCount`.
        final rend2 = [for (final id in real.take(20)) '$id-rend2'];
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.highlightAll([...real, ...rend2]);
        expect(notifications, 1);
        expect(controller.highlightedCount, 50);
        for (final id in real) {
          expect(controller.isHighlighted(id), isTrue);
          expect(controller.colorOf(id), kDefaultHighlightColor);
        }
        for (final id in rend2) {
          expect(
            controller.isHighlighted(id),
            isTrue,
            reason: '$id resolve à mesma nota que já está acesa',
          );
          expect(controller.colorOf(id), kDefaultHighlightColor);
        }
        controller.clearAll();
      },
    );

    testWidgets('o Ticker roda só com animação ativa', (tester) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      expect(controller.tickerActive, isFalse);
      controller.highlight(
        noteIds[0],
        release: const Duration(milliseconds: 300),
      );
      expect(controller.tickerActive, isTrue);
      await tester.pump(); // primeiro frame: relógio em 0
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.tickerActive, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.isHighlighted(noteIds[0]), isFalse);
      expect(controller.tickerActive, isFalse);
      expect(controller.colors, isEmpty);
      // Highlight instantâneo sem release nem attack também não deixa o ticker.
      controller.highlight(noteIds[0], release: Duration.zero);
      expect(controller.tickerActive, isFalse);
      expect(controller.colors, isEmpty);
    });

    testWidgets('acender uma nota no meio do release a reinicia e só ela', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      final ids = noteIds.take(50).toList();
      controller.highlightAll(
        ids,
        attack: const Duration(milliseconds: 100),
        hold: const Duration(milliseconds: 100),
        release: const Duration(milliseconds: 400),
      );
      await tester.pump();
      // Escalona: cada nota entra num instante diferente do relógio.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        controller.highlight(
          ids[i],
          attack: const Duration(milliseconds: 100),
          hold: const Duration(milliseconds: 100),
          release: const Duration(milliseconds: 400),
        );
      }
      await tester.pump(const Duration(milliseconds: 300)); // ~no release
      final target = ids[30];
      final others = {
        for (final id in ids)
          if (id != target) id: controller.colorOf(id),
      };
      final before = controller.colorOf(target);
      controller.highlight(target, color: const Color(0xFF00FF00));
      // Imediatamente: a nota reiniciada foi para a cor nova (attack 0)...
      expect(controller.colorOf(target), const Color(0xFF00FF00));
      expect(controller.colorOf(target), isNot(before));
      // ...e as outras 49 não mudaram.
      for (final e in others.entries) {
        expect(controller.colorOf(e.key), e.value, reason: e.key);
      }
      controller.clearAll();
    });

    testWidgets(
      'clearAll no meio de 50 fades: página byte-idêntica ao repouso',
      (tester) async {
        final controller = ScoreController();
        addTearDown(controller.dispose);
        await mount(tester, doc, controller);
        final rest = await shot(tester, doc);
        controller.setColor(noteIds[60], const Color(0xFF0000FF));
        controller.highlightAll(
          noteIds.take(50),
          attack: const Duration(milliseconds: 100),
          release: const Duration(milliseconds: 500),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          countDifferentPixels(rest, await shot(tester, doc)),
          greaterThan(0),
        );
        controller.clearAll();
        await tester.pump();
        expect(controller.tickerActive, isFalse);
        expect(countDifferentPixels(rest, await shot(tester, doc)), 0);
      },
    );

    testWidgets('releaseAll devolve as cores originais, inclusive @color', (
      tester,
    ) async {
      final blueId = noteIds[5];
      final blueDoc = loadSatieWithColors({blueId: '#0000ff'});
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, blueDoc, controller);
      final rest = await shot(tester, blueDoc);
      controller.highlightAll([
        ...noteIds.take(20),
        blueId,
      ], hold: const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // A nota azul foi de azul (`@color`) para vermelho.
      expect(controller.colorOf(blueId), kDefaultHighlightColor);
      controller.releaseAll(duration: const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      // No meio do release a nota azul está entre vermelho e AZUL (não preto).
      final mid = controller.colorOf(blueId)!;
      expect(mid.b, greaterThan(0.05));
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.colors, isEmpty);
      expect(controller.tickerActive, isFalse);
      expect(countDifferentPixels(rest, await shot(tester, blueDoc)), 0);
    });

    testWidgets('setColor vira a cor de repouso; a animação a sobrepõe', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      const green = Color(0xFF00AA00);
      final id = noteIds[0];
      controller.setColor(id, green);
      expect(controller.colorOf(id), green);
      // Destaque parte do verde e volta a ele — não ao preto original.
      controller.highlight(
        id,
        attack: const Duration(milliseconds: 100),
        release: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50)); // meio do attack
      final mid = controller.colorOf(id)!;
      expect(
        mid,
        isNot(anyOf(green, kDefaultHighlightColor)),
        reason: 'no meio do attack: entre verde e vermelho',
      );
      expect(mid.g, greaterThan(0.3)); // ainda tem o verde da base
      // Durante a animação, setColor só muda a base (destino do release).
      const blue = Color(0xFF0000FF);
      controller.setColor(id, blue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.isHighlighted(id), isFalse);
      expect(controller.colorOf(id), blue); // repousa no azul novo
      // clearColor devolve a original (sem override).
      controller.clearColor(id);
      expect(controller.colorOf(id), isNull);
    });

    testWidgets('clearColor durante o destaque faz o release ir à original', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      await mount(tester, doc, controller);
      final id = noteIds[0];
      controller.setColor(id, const Color(0xFF00AA00));
      controller.highlight(id, hold: const Duration(milliseconds: 100));
      controller.clearColor(id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.colorOf(id), isNull);
      expect(controller.colors, isEmpty);
    });

    testWidgets('sem Picture recompilado durante uma sequência de destaques', (
      tester,
    ) async {
      final controller = ScoreController();
      addTearDown(controller.dispose);
      final state = await mount(tester, doc, controller);
      final builds = state.pictureBuilds;
      controller.highlightAll(
        noteIds.take(64),
        attack: const Duration(milliseconds: 50),
        release: const Duration(milliseconds: 200),
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await shot(tester, doc);
      }
      expect(state.pictureBuilds, builds);
    });
  });
}

final _key = GlobalKey();

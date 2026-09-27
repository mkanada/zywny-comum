// `ScorePlayer` (A05a/A05b): relógio, timemap → destaque, viradas.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/fake_doc.dart';
import 'support/render_helpers.dart';

/// Ids visíveis para o controller (percurso sem `hidden`), para comparar com
/// o que o timemap manda acender.
Set<String> knownIds(VsbDocument doc) {
  final ids = <String>{};
  for (final page in doc.pages) {
    walkScene(page.root, const ui.Color(0xFF000000), _Ids(ids));
  }
  return ids;
}

class _Ids implements SceneVisitor {
  _Ids(this.ids);
  final Set<String> ids;
  @override
  bool enterGroup(SceneNode node, ui.Color a, ui.Color b) {
    if (node.id != null) ids.add(node.id!);
    return true;
  }

  @override
  void visitLeaf(SceneChild leaf, ui.Color color) {}
  @override
  void exitGroup(SceneNode node) {}
}

/// As notas que o timemap diz estarem ativas em [ms], resolvidas ao id da
/// cena (E02a: um `-rend2` de repetição vira a base, do mesmo jeito que
/// `ScoreController` resolve antes de acender).
Set<String> activeAt(VsbDocument doc, double ms) {
  final active = <String>{};
  for (final e in doc.timemap!) {
    if (e.tstamp > ms) break;
    active.removeAll(e.off.map((id) => doc.sceneIdOf(id) ?? id));
    active.addAll(e.on.map((id) => doc.sceneIdOf(id) ?? id));
  }
  return active;
}

/// Guarda de limpeza: o Ticker do controller/player não pode sobreviver ao
/// teste, e `addTearDown` roda tarde demais para a verificação do binding.
class Cleanup {
  final List<void Function()> _fns = [];
  void add(void Function() fn) => _fns.add(fn);
  void run() {
    for (final fn in _fns.reversed) {
      fn();
    }
  }
}

/// Relógio com posição setável à mão — prova mínima do contrato de
/// [PlaybackClock] e exemplo de uso (`ScorePlayer.clock`, C01).
class ManualClock implements PlaybackClock {
  @override
  double positionMs = 0;
  @override
  bool isRunning = true;
}

void testPlayer(
  String name,
  Future<void> Function(WidgetTester tester, Cleanup cleanup) body,
) {
  testWidgets(name, (tester) async {
    final cleanup = Cleanup();
    try {
      await body(tester, cleanup);
    } finally {
      cleanup.run();
    }
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  final gymnopedie = corpusDoc('Gymnopedie');
  if (gymnopedie == null) {
    test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
    return;
  }

  ScorePlayer makePlayer(
    VsbDocument doc,
    ScoreController controller, {
    ScoreViewController? view,
    void Function(TimemapEntry)? onEntry,
  }) => ScorePlayer(
    document: doc,
    controller: controller,
    view: view,
    release: Duration.zero,
    onEntry: onEntry,
  );

  group('consistência com o timemap (A05a, critério 1)', () {
    for (final name in ['Gymnopedie', 'Scarlatti', 'Nocturne']) {
      testPlayer(name, (tester, cleanup) async {
        final doc = corpusDoc(name)!;
        final known = knownIds(doc);
        final controller = ScoreController(document: doc);
        final player = makePlayer(doc, controller);
        cleanup.add(() {
          controller.clearAll();
          player.dispose();
          controller.dispose();
        });
        final rng = math.Random(5);
        // 20 instantes sorteados, por seek.
        for (var i = 0; i < 20; i++) {
          final ms = rng.nextDouble() * player.duration.inMilliseconds;
          player.seek(Duration(microseconds: (ms * 1000).round()));
          final expected = activeAt(doc, ms).intersection(known);
          expect(
            controller.highlightedIds.toSet(),
            expected,
            reason: '$name seek $ms',
          );
        }
        // E por avanço incremental em passos irregulares.
        player.seek(Duration.zero);
        var ms = 0.0;
        while (ms < player.duration.inMilliseconds) {
          final step = 1 + rng.nextInt(1500);
          ms += step;
          player.advance(Duration(milliseconds: step));
          final at = math.min(ms, player.duration.inMilliseconds.toDouble());
          expect(
            controller.highlightedIds.toSet(),
            activeAt(doc, at).intersection(known),
            reason: '$name avanço até $at',
          );
        }
      });
    }
  });

  testPlayer('Gymnopédie: destaque não-vazio durante toda a 2ª passagem (E02a, '
      'critério 3)', (tester, cleanup) async {
    final doc = corpusDoc('Gymnopedie')!;
    final known = knownIds(doc);
    final controller = ScoreController(document: doc);
    final player = makePlayer(doc, controller);
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    final rng = math.Random(7);
    for (var i = 0; i < 20; i++) {
      final ms = 92368 + rng.nextDouble() * (165789 - 92368);
      player.seek(Duration(microseconds: (ms * 1000).round()));
      final expected = activeAt(doc, ms).intersection(known);
      expect(controller.highlightedIds.toSet(), expected, reason: 'seek $ms');
      expect(
        controller.highlightedIds,
        isNotEmpty,
        reason: 'seek $ms não deveria ficar sem destaque nenhum',
      );
    }
  });

  testPlayer(
    'r13 (repetição de um compasso): a nota repetida acende de novo, sem '
    'ficar em release (E02a, critério 4)',
    (tester, cleanup) async {
      final bytes = File('test/fixtures/r13-um-compasso.vsb').readAsBytesSync();
      final doc = VsbDocument.fromBytes(bytes);
      final controller = ScoreController(document: doc);
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        release: Duration.zero,
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      // Timemap: on m1n1 em 0, off m1n1 + on m1n1-rend2 em 2000 (o mesmo
      // instante: a nota repetida), off m1n1-rend2 + on m2n1 em 4000.
      player.seek(Duration.zero);
      player.advance(const Duration(milliseconds: 2001));
      expect(
        controller.isHighlighted('m1n1'),
        isTrue,
        reason: 'a base deve reacender assim que a 2ª passagem começa',
      );
      // Bem depois do salto, mas antes do próximo off (4000 ms): se a nota
      // tivesse ficado presa no `release` de Duration.zero da 1ª passagem
      // (o bug de antes de E02a), já estaria apagada aqui.
      player.advance(const Duration(milliseconds: 1800));
      expect(controller.isHighlighted('m1n1'), isTrue);
      expect(controller.colorOf('m1n1'), kDefaultHighlightColor);
    },
  );

  testPlayer('toca a peça toda e termina com tudo apagado (critério 2)', (
    tester,
    cleanup,
  ) async {
    final doc = corpusDoc('Nocturne')!;
    expect(doc.pages.length, greaterThanOrEqualTo(3));
    final controller = ScoreController(document: doc);
    final player = ScorePlayer(document: doc, controller: controller);
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    player.play();
    player.speed = 50;
    var frames = 0;
    while (player.isPlaying && frames < 5000) {
      await tester.pump(const Duration(milliseconds: 100));
      frames++;
    }
    expect(player.isPlaying, isFalse);
    expect(player.position, player.duration);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.highlightedCount, 0);
    expect(controller.colors, isEmpty);
  });

  testPlayer('seek no meio: estado coerente e compasso certo (critério 3)', (
    tester,
    cleanup,
  ) async {
    final doc = corpusDoc('Scarlatti')!;
    final controller = ScoreController(document: doc);
    final player = makePlayer(doc, controller);
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    player.seek(const Duration(seconds: 30));
    final lit = controller.highlightedIds.toSet();
    final idx = player.currentMeasureIndex.value;
    final m = player.measures[idx];
    expect(m.startMs, lessThanOrEqualTo(30000));
    expect(m.endMs, greaterThan(30000));
    // Depois do seek para o início, nada resta preso.
    player.seek(Duration.zero);
    expect(
      controller.highlightedIds.toSet().intersection(lit),
      lit.intersection(activeAt(doc, 0)),
    );
    expect(player.currentMeasureIndex.value, 0);
    // Cor fixa do host sobrevive ao seek.
    final id = doc.pages[0].elements
        .firstWhere((e) => e.className == 'note')
        .id;
    controller.setColor(id, const ui.Color(0xFF00FF00));
    player.seek(const Duration(seconds: 10));
    expect(controller.colorOf(id) != null, isTrue);
  });

  testPlayer('speed 4 não perde nenhuma entrada (critério 4)', (
    tester,
    cleanup,
  ) async {
    final doc = corpusDoc('Scarlatti')!;
    Set<String> run(double speed, int stepMs) {
      final seen = <String>{};
      final controller = ScoreController(document: doc);
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        release: Duration.zero,
        onEntry: (e) => seen.addAll(e.on),
      )..speed = speed;
      player.play();
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      return seen;
    }

    // Executa 1x e 4x com pumps de tamanhos diferentes e compara os
    // conjuntos de notas acendidas.
    final seen1 = <String>{};
    final seen4 = <String>{};
    final c1 = ScoreController(document: doc);
    final c4 = ScoreController(document: doc);
    final p1 = ScorePlayer(
      document: doc,
      controller: c1,
      release: Duration.zero,
      onEntry: (e) => seen1.addAll(e.on),
    );
    final p4 = ScorePlayer(
      document: doc,
      controller: c4,
      release: Duration.zero,
      onEntry: (e) => seen4.addAll(e.on),
    )..speed = 4;
    cleanup.add(() {
      c1.clearAll();
      c4.clearAll();
      p1.dispose();
      p4.dispose();
      c1.dispose();
      c4.dispose();
    });
    p1.play();
    p4.play();
    var frames = 0;
    while ((p1.isPlaying || p4.isPlaying) && frames < 4000) {
      await tester.pump(const Duration(milliseconds: 250));
      frames++;
    }
    final all = <String>{for (final e in doc.timemap!) ...e.on};
    expect(seen1, all);
    expect(seen4, all);
    expect(run, isNotNull);
  });

  testPlayer('pause/play não movem a posição nem reiniciam fades '
      '(critério 5)', (tester, cleanup) async {
    final doc = corpusDoc('Scarlatti')!;
    final controller = ScoreController(document: doc);
    final player = ScorePlayer(document: doc, controller: controller);
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    player.play();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final at = player.position;
    expect(at, greaterThan(const Duration(seconds: 2)));
    player.pause();
    final held = activeAt(
      doc,
      at.inMicroseconds / 1000.0,
    ).intersection(knownIds(doc));
    expect(held, isNotEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(player.position, at, reason: 'pausado não anda');
    player.play();
    expect(player.position, at, reason: 'play não move');
    await tester.pump();
    expect(
      controller.highlightedIds.toSet().containsAll(held),
      isTrue,
      reason: 'notas seguradas continuam acesas',
    );
  });

  testPlayer('ids do timemap ausentes da cena passam sem erro (critério 6)', (
    tester,
    cleanup,
  ) async {
    final doc = gymnopedie;
    final known = knownIds(doc);
    final missing = {
      for (final e in doc.timemap!) ...[...e.on, ...e.off],
    }.difference(known);
    expect(
      missing.length,
      greaterThanOrEqualTo(100),
      reason: 'a Gymnopédie tem ~180 ids ausentes',
    );
    final controller = ScoreController(document: doc);
    final player = ScorePlayer(document: doc, controller: controller);
    cleanup.add(() {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    });
    player.speed = 30;
    player.play();
    var frames = 0;
    while (player.isPlaying && frames < 3000) {
      await tester.pump(const Duration(milliseconds: 100));
      frames++;
    }
    expect(player.isPlaying, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('virada automática dirigida pelo player (A05b)', () {
    testPlayer('peça inteira: viradas, sem exceção, última página em repouso '
        'sem haste, pixel-idêntica (critérios 1, 2 e 6)', (
      tester,
      cleanup,
    ) async {
      final doc = corpusDoc('Scarlatti')!;
      expect(doc.pages.length, greaterThanOrEqualTo(3));
      final controller = ScoreController(document: doc);
      final vc = ScoreViewController();
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final p0 = doc.pages[0];
      final key = await pumpAtSize(
        tester,
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
        p0.widthPx,
        p0.heightPx,
      );
      final turns = <int>[];
      vc.addListener(() => turns.add(vc.currentPage));
      var sawCurtain = false;
      player.curtain.addListener(() {
        if (player.curtain.value != null) sawCurtain = true;
      });
      player.speed = 20;
      player.play();
      var frames = 0;
      while (player.isPlaying && frames < 6000) {
        await tester.pump(const Duration(milliseconds: 50));
        frames++;
      }
      expect(tester.takeException(), isNull);
      expect(sawCurtain, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      final last = doc.pages.length - 1;
      expect(vc.currentPage, last);
      expect(turns, isNotEmpty);
      expect(player.curtain.value, isNull);
      expect(find.byType(ClipRect), findsNothing);
      final expected = await harnessBytes(tester, doc, last);
      final got = await captureBytes(tester, key, p0.widthPx, p0.heightPx);
      // Página final idêntica ao render estático, sem resíduo de haste.
      // (Todas as notas já foram apagadas: o repouso é a cena original.)
      expect(countDifferentPixels(expected, got), 0);
    });

    testPlayer('seek: dentro do último compasso, na página seguinte e antes '
        'da virada (critério 5)', (tester, cleanup) async {
      final doc = corpusDoc('Nocturne')!;
      final controller = ScoreController(document: doc);
      final vc = ScoreViewController();
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
        release: Duration.zero,
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final p0 = doc.pages[0];
      await pumpAtSize(
        tester,
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
        p0.widthPx,
        p0.heightPx,
      );
      final tl = player.timeline;
      final ms = player.measures;
      final i = ms.indexWhere(
        (m) => m.page == 0 && ms[ms.indexOf(m) + 1].page == 1,
      );
      final m = ms[i];
      final next = ms[i + 1];
      final barWidth = vc.barWidth;
      SweepCurtain? expectedAt(double t) =>
          tl.curtainAt(t, maxSweep: vc.maxSweepDuration, barWidth: barWidth);
      // Dentro do último compasso da página 0 (haste estacionada).
      final parked = (m.startMs + m.endMs) / 2;
      player.seek(Duration(milliseconds: parked.round()));
      await tester.pump();
      expect(player.curtain.value, expectedAt(parked));
      expect(player.curtain.value, isNotNull);
      expect(find.byType(ClipRect), findsOneWidget);
      // Na página seguinte (depois da conclusão): repouso, sem animação.
      final after = next.startMs + 5000.0;
      player.seek(Duration(milliseconds: after.round()));
      await tester.pump();
      expect(player.curtain.value, isNull);
      expect(vc.currentPage, next.page);
      expect(find.byType(ClipRect), findsNothing);
      // Antes da virada: repouso da página 0.
      player.seek(Duration.zero);
      await tester.pump();
      expect(player.curtain.value, isNull);
      expect(vc.currentPage, 0);
      expect(find.byType(ClipRect), findsNothing);
    });

    testPlayer('destaque atravessa a virada com o player (critério 6)', (
      tester,
      cleanup,
    ) async {
      final doc = corpusDoc('Nocturne')!;
      final controller = ScoreController(document: doc);
      final vc = ScoreViewController();
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
        release: const Duration(seconds: 2),
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final p0 = doc.pages[0];
      final key = await pumpAtSize(
        tester,
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
        p0.widthPx,
        p0.heightPx,
      );
      final ms = player.measures;
      final i = ms.indexWhere(
        (m) => m.page == 0 && ms[ms.indexOf(m) + 1].page == 1,
      );
      final m = ms[i];
      // Começa a tocar perto do fim do último compasso da página 0.
      player.seek(Duration(milliseconds: m.startMs));
      player.play();
      final samples = <(int, bool)>[];
      var frames = 0;
      while (vc.currentPage == 0 && frames < 2000) {
        await tester.pump(const Duration(milliseconds: 50));
        frames++;
        samples.add((
          controller.highlightedCount,
          player.curtain.value != null,
        ));
      }
      expect(vc.currentPage, 1);
      // Durante toda a virada havia notas acesas ou em fade: nunca zerou.
      final duringTurn = samples.where((s) => s.$2).toList();
      expect(duringTurn, isNotEmpty);
      expect(duringTurn.every((s) => s.$1 > 0), isTrue);
      await writePng(
        tester,
        await captureBytes(tester, key, p0.widthPx, p0.heightPx),
        p0.widthPx,
        p0.heightPx,
        '../compare/out/a05b/apos-virada.png',
      );
      player.pause();
    });

    testPlayer('modo contínuo: sem haste, a rolagem acompanha o compasso '
        '(critério 8)', (tester, cleanup) async {
      final doc = corpusDoc('Nocturne')!;
      final controller = ScoreController(document: doc);
      final vc = ScoreViewController();
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        view: vc,
        release: Duration.zero,
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final p0 = doc.pages[0];
      tester.view.physicalSize = ui.Size(
        p0.widthPx.toDouble(),
        p0.heightPx / 2,
      );
      tester.view.devicePixelRatio = 1.0;
      cleanup.add(tester.view.resetPhysicalSize);
      cleanup.add(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            mode: ScorePageMode.continuousScroll,
            curtain: player.curtain,
          ),
        ),
      );
      await tester.pump();
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      var maxJump = 0.0;
      var last = scroll.offset;
      var sawCurtain = false;
      player.curtain.addListener(() => sawCurtain = true);
      player.play();
      var frames = 0;
      // 60 s de execução em tempo real (1x), quadros de 50 ms.
      while (player.isPlaying && frames < 1200) {
        await tester.pump(const Duration(milliseconds: 50));
        maxJump = math.max(maxJump, (scroll.offset - last).abs());
        last = scroll.offset;
        frames++;
      }
      expect(sawCurtain, isFalse);
      expect(scroll.offset, greaterThan(0));
      // Animada (300 ms): nenhum quadro anda mais que meia viewport.
      expect(maxJump, lessThan(p0.heightPx / 2 / 2));
      // ignore: avoid_print
      print(
        'A05b contínuo: maior salto por frame = ${maxJump.round()} px '
        '(viewport ${p0.heightPx ~/ 2})',
      );
    });
  });

  group('compasso único dirigido pelo player (A05b, critério 4)', () {
    testPlayer('haste acompanha as notas e conclui na primeira do seguinte', (
      tester,
      cleanup,
    ) async {
      final doc = fakeDocument(
        [
          [
            FakeMeasure('m1', 100, [FakeNote('a1', 120)]),
            FakeMeasure('m2', 500, [FakeNote('a2', 520)]),
          ],
          [
            FakeMeasure('m3', 100, [
              FakeNote('b1', 150),
              FakeNote('b2', 300),
              FakeNote('b3', 450),
            ]),
          ],
          [
            FakeMeasure('m4', 100, [FakeNote('c1', 200)]),
          ],
        ],
        [
          (0, ['a1'], []),
          (4000, ['a2'], ['a1']),
          (8000, ['b1'], ['a2']),
          (10000, ['b2'], ['b1']),
          (12000, ['b3'], ['b2']),
          (16000, ['c1'], ['b3']),
          (20000, [], ['c1']),
        ],
      );
      final controller = ScoreController(document: doc);
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        barWidth: 50,
        release: Duration.zero,
      );
      cleanup.add(() {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      });
      final edges = <double>[];
      player.curtain.addListener(() {
        final c = player.curtain.value;
        if (c != null && c.pageIndex == 1) edges.add(c.edgeX);
      });
      player.seek(const Duration(milliseconds: 8000));
      // Avança em passos de 100 ms musicais pela página 1.
      for (var t = 8000; t < 17500; t += 100) {
        player.advance(const Duration(milliseconds: 100));
      }
      expect(edges, isNotEmpty);
      // Nunca vai para trás dentro da página, e chega antes de b3 (450).
      for (var i = 1; i < edges.length; i++) {
        expect(edges[i], greaterThanOrEqualTo(edges[i - 1] - 1e-9));
      }
      expect(edges.contains(450), isTrue);
      expect(edges.last, greaterThan(450), reason: 'conclusão em curso');
    });
  });

  group('relógio plugável (C01)', () {
    testPlayer(
      'ManualClock em saltos irregulares acende os mesmos ids que `advance` '
      '(critério 2, reusa a comparação do critério 4 de A05a)',
      (tester, cleanup) async {
        final doc = corpusDoc('Scarlatti')!;
        final durationMs = ScoreTimeline(doc).durationMs;
        final rng = math.Random(11);
        final steps = <int>[];
        var ms = 0.0;
        while (ms < durationMs) {
          final step = 1 + rng.nextInt(1500);
          steps.add(step);
          ms += step;
        }

        final seenAdvance = <String>{};
        final controllerA = ScoreController(document: doc);
        final playerA = ScorePlayer(
          document: doc,
          controller: controllerA,
          release: Duration.zero,
          onEntry: (e) => seenAdvance.addAll(e.on),
        );
        for (final step in steps) {
          playerA.advance(Duration(milliseconds: step));
        }

        final seenClock = <String>{};
        final controllerC = ScoreController(document: doc);
        final clock = ManualClock();
        final playerC =
            ScorePlayer(
              document: doc,
              controller: controllerC,
              release: Duration.zero,
              onEntry: (e) => seenClock.addAll(e.on),
            )..clock = clock;
        playerC.play();
        for (final step in steps) {
          clock.positionMs += step;
          await tester.pump(const Duration(milliseconds: 16));
        }

        cleanup.add(() {
          controllerA.clearAll();
          controllerC.clearAll();
          playerA.dispose();
          playerC.dispose();
          controllerA.dispose();
          controllerC.dispose();
        });

        expect(seenClock, seenAdvance);
      },
    );

    testPlayer(
      'ManualClock parado (posição não anda) por 100 frames: nada muda, sem '
      'exceção — modo espera (critério 3)',
      (tester, cleanup) async {
        final doc = corpusDoc('Scarlatti')!;
        final controller = ScoreController(document: doc);
        final clock = ManualClock()..positionMs = 30000;
        final player =
            ScorePlayer(document: doc, controller: controller, release: Duration.zero)
              ..clock = clock;
        cleanup.add(() {
          controller.clearAll();
          player.dispose();
          controller.dispose();
        });
        player.seek(Duration(milliseconds: clock.positionMs.round()));
        final lit = controller.highlightedIds.toSet();
        final index = player.currentMeasureIndex.value;
        player.play();
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(controller.highlightedIds.toSet(), lit);
        expect(player.currentMeasureIndex.value, index);
        expect(player.position, const Duration(milliseconds: 30000));
      },
    );

    testPlayer(
      'ManualClock: recuo de 5 s refaz como `seek`; recuo de 10 ms é '
      'ignorado (critério 4)',
      (tester, cleanup) async {
        final doc = corpusDoc('Scarlatti')!;
        final controller = ScoreController(document: doc);
        final clock = ManualClock()..positionMs = 30000;
        final player =
            ScorePlayer(document: doc, controller: controller, release: Duration.zero)
              ..clock = clock;
        cleanup.add(() {
          controller.clearAll();
          player.dispose();
          controller.dispose();
        });
        player.play();
        await tester.pump(const Duration(milliseconds: 16));
        expect(player.position, const Duration(milliseconds: 30000));

        // Recuo de 10 ms: jitter do relógio de áudio interpolado — ignorado.
        clock.positionMs -= 10;
        await tester.pump(const Duration(milliseconds: 16));
        expect(player.position, const Duration(milliseconds: 30000));

        // Recuo de 5 s: o host fez seek no áudio — refaz o estado do zero,
        // igual a `seek` para aquele instante.
        clock.positionMs = 25000;
        await tester.pump(const Duration(milliseconds: 16));
        expect(player.position, const Duration(milliseconds: 25000));
        final viaClock = controller.highlightedIds.toSet();

        final controller2 = ScoreController(document: doc);
        final player2 = ScorePlayer(
          document: doc,
          controller: controller2,
          release: Duration.zero,
        );
        cleanup.add(() {
          controller2.clearAll();
          player2.dispose();
          controller2.dispose();
        });
        player2.seek(const Duration(milliseconds: 25000));
        expect(viaClock, controller2.highlightedIds.toSet());
      },
    );
  });
}

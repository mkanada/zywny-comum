// Evidência e orçamento de frame de A02c.
//
//   flutter test tool/a02c_evidence.dart
//
// 1. Roteiro determinístico na página 1 da Gymnopédie, com o tempo dirigido
//    pelo relógio simulado do teste (não há captura "ao vivo"):
//      t=0     acorde de 4 notas   cor #D32F2F  attack 100  hold 150  release 700  easeOut
//      t=180   voz separada (2 n.) cor #1565C0  attack 40   hold 100  release 500  easeInOut
//    Cinco frames em t = 60, 200, 320, 480, 750 ms vão para
//    ../compare/out/a02/ (página inteira e recorte).
// 2. Custo de frame com 64 notas animando: mediana de 100 `pump` de 16 ms.
// 3. `pictureBuilds` antes e depois de tudo.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

Iterable<SceneNode> _descendants(SceneNode node) sync* {
  yield node;
  for (final child in node.children) {
    if (child is SceneNode) {
      yield* _descendants(child);
    }
  }
}

double _median(List<num> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2].toDouble();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadScoreFonts();

  testWidgets('A02c: roteiro, frames e orçamento', (tester) async {
    final doc = VsbDocument.fromBytes(
      File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
    );
    final page = doc.pages[0];
    final timemapIds = animatableIdsFromTimemap(doc.timemap);
    final nodes = _descendants(page.root).toList();

    // Acorde: as notas do primeiro `chord` da página com >= 3 notas.
    int noteCount(SceneNode chord) =>
        _descendants(chord)
            .where((c) => c.className == 'note' && timemapIds.contains(c.id))
            .length;
    // O acorde com mais notas da página (o primeiro, em caso de empate).
    final chord = nodes
        .where((n) => n.className == 'chord')
        .reduce((a, b) => noteCount(b) > noteCount(a) ? b : a);
    final chordNotes = [
      for (final n in _descendants(chord))
        if (n.className == 'note' && timemapIds.contains(n.id)) n,
    ].take(4).toList();
    final inChord = {for (final n in _descendants(chord)) n.id};
    // Voz: notas fora de qualquer acorde, mais adiante na página.
    final chordIds = {
      for (final c in nodes.where((n) => n.className == 'chord'))
        for (final n in _descendants(c)) n.id,
    };
    final voice = [
      for (final n in nodes)
        if (n.className == 'note' &&
            !n.hidden &&
            timemapIds.contains(n.id) &&
            !chordIds.contains(n.id) &&
            !inChord.contains(n.id))
          n,
    ].take(2).toList();
    expect(chordNotes.length, greaterThanOrEqualTo(3));
    expect(voice, isNotEmpty);
    print('acorde: ${[for (final n in chordNotes) n.id]}');
    print('voz   : ${[for (final n in voice) n.id]}');

    tester.view.physicalSize = ui.Size(
      page.widthPx.toDouble(),
      page.heightPx.toDouble(),
    );
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScoreController();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: ScorePageView(
            document: doc,
            pageIndex: 0,
            controller: controller,
          ),
        ),
      ),
    );
    final state = tester.state<ScorePageViewState>(find.byType(ScorePageView));
    final buildsBefore = state.pictureBuilds;

    final out = Directory('../compare/out/a02')..createSync(recursive: true);
    final region = () {
      var r = chordNotes.first.bbox!;
      for (final n in [...chordNotes, ...voice]) {
        r = r.expandToInclude(n.bbox!);
      }
      final f = page.fit;
      return ui.Rect.fromLTRB(
        f.tx + (r.left + page.origin.dx) * f.scale,
        f.ty + (r.top + page.origin.dy) * f.scale,
        f.tx + (r.right + page.origin.dx) * f.scale,
        f.ty + (r.bottom + page.origin.dy) * f.scale,
      ).inflate(60);
    }();

    Future<void> shot(int t) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final full = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      File('${out.path}/gymnopedie-t${t.toString().padLeft(4, '0')}.png')
          .writeAsBytesSync(full.buffer.asUint8List());
      final crop = region.intersect(
        ui.Rect.fromLTWH(
          0,
          0,
          page.widthPx.toDouble(),
          page.heightPx.toDouble(),
        ),
      );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        crop,
        ui.Offset.zero & crop.size,
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      final picture = recorder.endRecording();
      final cropped = (await tester.runAsync(
        () => picture.toImage(crop.width.round(), crop.height.round()),
      ))!;
      final png = (await tester.runAsync(
        () => cropped.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      File(
        '${out.path}/gymnopedie-t${t.toString().padLeft(4, '0')}-recorte.png',
      ).writeAsBytesSync(png.buffer.asUint8List());
      image.dispose();
      cropped.dispose();
      picture.dispose();
    }

    String hex(ui.Color? c) => c == null
        ? 'repouso'
        : '#${c.toARGB32().toRadixString(16).substring(2)}';

    var t = 0;
    Future<void> advanceTo(int target) async {
      await tester.pump(Duration(milliseconds: target - t));
      t = target;
    }

    controller.highlightAll(
      [for (final n in chordNotes) n.id!],
      color: const ui.Color(0xFFD32F2F),
      attack: const Duration(milliseconds: 100),
      hold: const Duration(milliseconds: 150),
      release: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
    await tester.pump(); // primeiro frame do Ticker: relógio do controller em 0
    final frames = <int, Map<String, ui.Color?>>{};
    for (final target in [60, 180, 200, 320, 480, 750]) {
      await advanceTo(target);
      if (target == 180) {
        controller.highlightAll(
          [for (final n in voice) n.id!],
          color: const ui.Color(0xFF1565C0),
          attack: const Duration(milliseconds: 40),
          hold: const Duration(milliseconds: 100),
          release: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        continue;
      }
      frames[target] = {
        for (final n in [...chordNotes, ...voice])
          n.id!: controller.colorOf(n.id!),
      };
      await shot(target);
    }
    print('--- fases por frame (cor de cada nota destacada)');
    for (final e in frames.entries) {
      print(
        't=${e.key} ms: ${e.value.entries.map((x) => '${x.key}=${hex(x.value)}').join('  ')}',
      );
      final distinct = {...e.value.values}..remove(null);
      if (e.key >= 200) {
        expect(
          distinct.length,
          greaterThanOrEqualTo(2),
          reason: 'frame ${e.key}: cores distintas convivendo',
        );
      }
    }
    await tester.pump(const Duration(seconds: 2));
    expect(controller.colors, isEmpty);
    expect(controller.tickerActive, isFalse);

    // --- orçamento: 64 notas animando
    final ids64 = [
      for (final n in nodes)
        if (n.className == 'note' && !n.hidden && timemapIds.contains(n.id))
          n.id!,
    ].take(64).toList();
    expect(ids64, hasLength(64));
    controller.highlightAll(
      ids64,
      attack: const Duration(seconds: 3),
      hold: const Duration(seconds: 1),
      release: const Duration(seconds: 3),
      curve: Curves.easeInOut,
    );
    await tester.pump();
    final frameMicros = <int>[];
    for (var i = 0; i < 100; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frameMicros.add(sw.elapsedMicroseconds);
    }
    final mean =
        frameMicros.reduce((a, b) => a + b) / frameMicros.length / 1000;
    print(
      '--- 64 notas animando, 100 frames de 16 ms (tick + notify + build + paint)',
    );
    print(
      'mediana ${(_median(frameMicros) / 1000).toStringAsFixed(3)} ms · '
      'média ${mean.toStringAsFixed(3)} ms · '
      'máx ${(frameMicros.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(3)} ms',
    );
    expect(controller.highlightedCount, 64);
    controller.clearAll();
    await tester.pump();
    print('pictureBuilds: antes=$buildsBefore depois=${state.pictureBuilds}');
    expect(state.pictureBuilds, buildsBefore);
  });
}

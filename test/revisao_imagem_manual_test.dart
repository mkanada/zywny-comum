// Gera a imagem da revisão do treino com o código de verdade: uma sessão de
// tempo real (PracticeController + agendador + notas MIDI simuladas) sobre a
// Gymnopédie já gravada, as marcas viram fantasmas fixas (GhostController) e
// a página sai do ScoreView com a ReviewBar por cima.
//
//   REVISAO_PNG=/caminho/revisao.png flutter test test/revisao_imagem_manual_test.dart
//
// `REVISAO_CENARIO=atrasada` toca só uma tecla certa, 120 ms depois do tempo.
@Tags(['manual'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_controller.dart';
import 'package:zywny/practice/review_bar.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';

import 'support/practice_fakes.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
    await _loadFont(
      'Roboto',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    );
    await _loadFont(
      'MaterialIcons',
      '/home/mauricio/development_tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  testWidgets('imagem da revisão', (tester) async {
    final out = Platform.environment['REVISAO_PNG'] ?? 'revisao.png';
    final bytes = File('test/fixtures/satie-fantasma.vsb').readAsBytesSync();
    final doc = VsbDocument.fromBytes(Uint8List.fromList(bytes));
    final track = PerformanceTrack.fromDocument(doc);
    final timeline = ScoreTimeline(doc);

    final engine = FakeSoundEngine();
    final scheduler = ScoreAudioScheduler(
      engine: engine,
      track: track,
      autoTick: false,
    );
    final scoreController = ScoreController(document: doc);
    final ghosts = GhostController()..attachDocument(doc);
    final midi = FakeMidiInput();
    final practice = PracticeController(
      midiInput: midi,
      track: track,
      scheduler: scheduler,
      controller: scoreController,
      hand: Hand.direita,
      ghosts: ghosts,
      mode: PracticeMode.realtime,
      measureIndexAt: timeline.measureIndexAt,
    );

    // Os instantes (acordes) da mão direita, na ordem.
    final mine = track.events
        .where(
          (e) => Hand.direita.studentStaves.contains(e.staff) && !e.ornament,
        )
        .toList();
    final instants = <double>{for (final e in mine) e.onMs}.toList()..sort();
    List<SoundEvent> at(double ms) => mine.where((e) => e.onMs == ms).toList();

    final onlyLate = Platform.environment['REVISAO_CENARIO'] == 'atrasada';
    // Plano do aluno: (instante, deslocamento em ms, altura trocada?).
    // Deslocamento negativo = antes do tempo; positivo = depois.
    // Altura trocada: toca uma tecla vizinha que a partitura não pede ali.
    final plan = <(double, double, bool)>[];
    for (var i = 0; i < instants.length && i < 14; i++) {
      final (shift, wrong) = onlyLate
          ? (i == 3 ? (120.0, false) : (0.0, false))
          : switch (i) {
              3 => (-120.0, false), // a tecla certa, adiantada
              5 => (130.0, false), // a tecla certa, atrasada
              7 => (-100.0, true), // a tecla errada, antes
              9 => (110.0, true), // a tecla errada, depois
              _ => (0.0, false),
            };
      plan.add((instants[i], shift, wrong));
    }
    final presses = <(double, int)>[];
    for (final (ms, shift, wrong) in plan) {
      for (final e in at(ms)) {
        var pitch = e.pitch;
        if (wrong) {
          pitch += 2;
          while (mine.any(
            (o) => o.pitch == pitch && (o.onMs - ms).abs() < 400,
          )) {
            pitch++;
          }
        }
        presses.add((ms + shift, pitch));
      }
    }
    presses.sort((a, b) => a.$1.compareTo(b.$1));

    practice.start();
    for (final (ms, pitch) in presses) {
      var guard = 0;
      while (scheduler.positionMs < ms && guard++ < 100000) {
        engine.now += 0.005;
        scheduler.pump();
      }
      midi.press(pitch, atSeconds: engine.now);
      await tester.pump();
      midi.release(pitch, atSeconds: engine.now + 0.05);
      await tester.pump();
    }
    practice.finish();
    final marks = practice.wrongMarks;
    practice.stop();

    // ignore: avoid_print
    print(
      'marcas: ${[for (final m in marks) '${m.offBeat ? "tempo" : "altura"}:'
            '${m.pitch}:${m.side}'].join('  ')}',
    );
    if (onlyLate) {
      expect(marks.map((m) => (m.offBeat, m.side)), everyElement((true, 1)));
      expect(marks, isNotEmpty);
    } else {
      expect(marks.where((m) => m.side < 0 && m.offBeat), isNotEmpty);
      expect(marks.where((m) => m.side > 0 && m.offBeat), isNotEmpty);
      expect(marks.where((m) => m.side < 0 && !m.offBeat), isNotEmpty);
      expect(marks.where((m) => m.side > 0 && !m.offBeat), isNotEmpty);
    }

    ghosts.setReview([for (final m in marks) m.ghostRequest]);
    final page = doc.pages[0];
    final w = page.widthPx, h = page.heightPx;
    tester.view.physicalSize = ui.Size(w.toDouble(), h.toDouble());
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: key,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ScoreView(
                    document: doc,
                    controller: scoreController,
                    mode: ScorePageMode.pagedSweep,
                    ghosts: ghosts,
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Center(
                    child: ReviewBar(
                      count: marks.length,
                      reviewing: true,
                      hasSides: true,
                      onReview: () {},
                      onPrevious: null,
                      onNext: null,
                      onClose: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(out).writeAsBytesSync(png!);
    // Recorte ampliado do primeiro sistema, onde estão as marcas.
    final zoom = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final src = onlyLate
          ? const ui.Rect.fromLTWH(780, 40, 760, 420)
          : const ui.Rect.fromLTWH(800, 20, 1300, 500);
      final scale = onlyLate ? 2.6 : 1.6;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        src,
        ui.Rect.fromLTWH(0, 0, src.width * scale, src.height * scale),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(
        (src.width * scale).round(),
        (src.height * scale).round(),
      );
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(out.replaceFirst('.png', '_zoom.png')).writeAsBytesSync(zoom!);
    // ignore: avoid_print
    print('página ${w}x$h -> $out');

    practice.dispose();
    ghosts.dispose();
    scoreController.dispose();
    midi.dispose();
  });
}

// Teste manual: modo espera no 1º trecho do hino 559, com o render Verovio
// de verdade e as peças ligadas como no app (agendador + relógio de áudio no
// player + `PracticeController` com intervalo). O teclado é simulado: em cada
// passo, a nota pendente precisa estar acesa (azul) antes de o aluno tocar,
// uma nota certa fica verde só enquanto apertada e o passo só avança com o
// acorde todo apertado.
//
// Depende da libverovio.so do verovio_flutter_bridge (pulado sem ela):
//
//   flutter test test/hino559_espera_manual_test.dart
@Tags(['manual'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/hymn_package.dart';

import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/audio/audio_playback_clock.dart';
import 'package:zywny/audio/score_audio_scheduler.dart';
import 'package:zywny/audio/sound_engine.dart';
import 'package:zywny/midi/midi_input_service.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/practice/app_hand.dart';
import 'package:zywny/practice/practice_colors.dart';
import 'package:zywny/practice/practice_controller.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/trail/trail_stage.dart';
import 'package:zywny/verovio_render.dart';

import 'support/render_helper.dart';

class _Engine implements SoundEngine {
  double now = 0;
  @override
  double get nowSeconds => now;
  @override
  double get earliestScheduleSeconds => now + 0.02;
  @override
  double get outputLatencySeconds => 0.02;
  @override
  Future<void> start() async {}
  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}
  @override
  void send(List<int> midi) {}
  @override
  void schedule(List<ScheduledMidi> events) {}
  @override
  void clearScheduled() {}
  @override
  void allNotesOff() {}
  @override
  Future<void> dispose() async {}
}

class _Midi implements MidiInputService {
  final _notes = StreamController<PlayedNote>.broadcast();
  final _sustain = StreamController<int>.broadcast();
  final _held = ValueNotifier<Set<int>>(const {});
  @override
  Stream<PlayedNote> get notes => _notes.stream;
  @override
  Stream<int> get sustain => _sustain.stream;
  @override
  ValueListenable<Set<int>> get held => _held;
  void key(int pitch, {required bool on, required double at}) => _notes.add(
    PlayedNote(
      pitch: pitch,
      velocity: on ? 80 : 0,
      channel: 0,
      on: on,
      atSeconds: at,
    ),
  );
  @override
  void dispose() {}
}

void main() {
  final missing = !File(kLibverovioPath).existsSync();
  test(
    '559, trecho 1, notas de cada mão: nota pendente acesa e passo avança',
    skip: missing ? 'sem libverovio.so' : null,
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tmp = await Directory.systemTemp.createTemp('h559');
      addTearDown(() => tmp.delete(recursive: true));
      final hymns = await openLocalHymnPackage();
      if (hymns == null) {
        markTestSkipped('sem dist/hinos.zywny e keys/ (just pacote-hinos)');
        return;
      }
      final input = File('${tmp.path}/559.musicxml')
        ..writeAsBytesSync(await hymns.loadScore('559'));
      final doc = await renderScoreToVsb(
        VsbRenderRequest(
          inputPath: input.path,
          outputPath: '${tmp.path}/559.vsb',
          libraryPath: kLibverovioPath,
          resourcePath: kVerovioDataPath,
          pageWidth: kFallbackPageWidth,
          pageHeight: kFallbackPageHeight,
        ),
      );
      final track = PerformanceTrack.fromDocument(doc);
      final path = TrailPath.fromTimeline(ScoreTimeline(doc));
      final plan = TrailPlan.build(path, track, n: kTrailDefaultMeasures);
      final problems = <String>[];

      for (final legato in [false, true]) {
        for (final stageId in ['t0.notasD', 't0.notasE', 't0.notasJ']) {
          final id = legato ? '$stageId (legato)' : stageId;
          final stage = plan.stages.firstWhere((s) => s.id == stageId);
          var held = <int>{};
          final engine = _Engine();
          final scheduler = ScoreAudioScheduler(
            engine: engine,
            track: track,
            autoTick: false,
          );
          final controller = ScoreController(document: doc);
          final player = ScorePlayer(
            document: doc,
            controller: controller,
            highlightColor: kPracticePendingColor,
            mergeTies: true,
          )..clock = AudioPlaybackClock(scheduler);
          // Como no app: no modo espera as notas do aluno são do
          // PracticeController, o player não as acende.
          final studentNotes = {
            for (final id in studentHandNoteIds(track, stage.phase.hand)) ...[
              id,
              doc.sceneIdOf(id) ?? id,
            ],
          };
          player.skipHighlight = studentNotes.contains;
          final midi = _Midi();
          var done = false;
          final practice = PracticeController(
            midiInput: midi,
            track: track,
            scheduler: scheduler,
            controller: controller,
            hand: stage.phase.hand,
            measureIndexAt: player.timeline.measureIndexAt,
            range: (startMs: stage.startMs, endMs: stage.endMs),
            onRangeDone: () => done = true,
            onWaitTarget: (ms) => player.waitTarget = ms,
          );
          player.seek(Duration(microseconds: (stage.startMs * 1000).round()));
          practice.start();

          void sync() {
            for (var i = 0; i < 400; i++) {
              final before = scheduler.positionMs;
              engine.now += 0.016;
              scheduler.pump();
              final ms = scheduler.positionMs;
              if (ms > player.position.inMicroseconds / 1000) {
                player.advance(
                  Duration(
                    microseconds:
                        ((ms - player.position.inMicroseconds / 1000) * 1000)
                            .round(),
                  ),
                );
              }
              if (ms == before && i > 4) break;
            }
          }

          var guard = 0;
          while (!done && guard++ < 200) {
            sync();
            final step = practice.currentStep.value;
            if (step == null) break;
            final pendingColor = <String>[];
            for (final e in step.notes) {
              final ids = {e.id, doc.sceneIdOf(e.id) ?? e.id};
              final on = ids.any((i) => controller.colorOf(i) != null);
              final color = ids
                  .map(controller.colorOf)
                  .whereType<Color>()
                  .firstOrNull;
              if (!on || color != kPracticePendingColor) {
                pendingColor.add('${e.pitch}:${on ? color : 'apagada'}');
              }
            }
            if (pendingColor.isNotEmpty) {
              problems.add(
                '$id passo ${step.index} @${step.onMs.toStringAsFixed(1)} '
                'pos=${scheduler.positionMs.toStringAsFixed(1)} '
                'player=${player.position.inMilliseconds} '
                'não acesas: $pendingColor',
              );
            }
            final t = engine.now;
            final pitches = step.notes.map((e) => e.pitch).toSet();
            if (legato) {
              // Nota repetida precisa soltar antes; as outras do acorde
              // anterior só soltam depois de o novo estar apertado. As do
              // acorde entram uma a uma, 30 ms entre elas.
              for (final p in held.intersection(pitches)) {
                midi.key(p, on: false, at: t);
              }
              var k = 0;
              for (final p in pitches) {
                midi.key(p, on: true, at: t + 0.03 * k++);
                await pumpEventQueue();
              }
              for (final p in held.difference(pitches)) {
                midi.key(p, on: false, at: t + 0.03 * k);
              }
              held = pitches;
            } else {
              // Antes, uma nota do acorde sozinha: verde enquanto apertada;
              // solta, o acorde volta todo a azul e o passo não anda.
              if (pitches.length > 1) {
                midi.key(pitches.first, on: true, at: t);
                await pumpEventQueue();
                final alone = step.notes.firstWhere(
                  (e) => e.pitch == pitches.first,
                );
                final aloneColor =
                    controller.colorOf(doc.sceneIdOf(alone.id) ?? alone.id) ??
                    controller.colorOf(alone.id);
                if (aloneColor != kPracticeCorrectColor) {
                  problems.add(
                    '$id passo ${step.index}: nota ${pitches.first} apertada '
                    'sozinha não ficou verde ($aloneColor)',
                  );
                }
                midi.key(pitches.first, on: false, at: t + 0.1);
                await pumpEventQueue();
                final still = practice.currentStep.value;
                final colors = [
                  for (final e in step.notes)
                    controller.colorOf(doc.sceneIdOf(e.id) ?? e.id) ??
                        controller.colorOf(e.id),
                ];
                if (still?.index != step.index ||
                    colors.any((c) => c != kPracticePendingColor)) {
                  problems.add(
                    '$id passo ${step.index}: nota ${pitches.first} sozinha '
                    'mudou o acorde (cores $colors, passo ${still?.index})',
                  );
                }
              }
              // O aluno toca o acorde junto e solta antes do próximo.
              for (final p in pitches) {
                midi.key(p, on: true, at: t);
              }
            }
            await pumpEventQueue();
            final after = practice.currentStep.value;
            if (!done && after != null && after.index == step.index) {
              problems.add(
                '$id passo ${step.index}: acorde inteiro tocado e não avançou '
                '(faltam ${after.remaining})',
              );
              break;
            }
            if (!legato) {
              for (final p in pitches) {
                midi.key(p, on: false, at: t + 0.2);
              }
              await pumpEventQueue();
            }
          }
          if (!done) problems.add('$id: etapa não terminou');
          practice.dispose();
          player.dispose();
          controller.dispose();
        }
      }
      for (final p in problems) {
        // ignore: avoid_print
        print(p);
      }
      expect(problems, isEmpty);
    },
  );
}

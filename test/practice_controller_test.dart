// T02: `PracticeController` de ponta a ponta — `FakeMidiInput` (não existe
// dublê real ainda; mesmo estilo do `FakeMidiSender` de
// test/midi_out_sound_engine_test.dart) alimentando um `ScoreAudioScheduler`
// real (com um `FakeSoundEngine`, mesmo estilo de
// test/score_audio_scheduler_test.dart) e um `ScoreController` real sobre o
// corpus, para conferir a integração toda: nota certa avança o freio e pinta
// verde; nota errada não avança, pisca a nota esperada mais próxima e marca
// a tecla física errada.
//
// `test()` puro (não `testWidgets`): não há árvore de widget nenhuma para
// montar, só `ScoreController`/`Ticker` (por isso o
// `TestWidgetsFlutterBinding.ensureInitialized()` em `setUpAll`, mesmo
// padrão de `score_bridge/test/score_player_test.dart`) e o `pumpEventQueue`
// para esvaziar os microtasks do stream de notas (broadcast comum, sem
// `sync: true`, igual ao `FlutterMidiInputService` de verdade).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/audio/score_audio_scheduler.dart';
import 'package:zywny/audio/sound_engine.dart';
import 'package:zywny/midi/midi_input_service.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_colors.dart';
import 'package:zywny/practice/practice_controller.dart';

class FakeSoundEngine implements SoundEngine {
  double now = 0;
  final List<ScheduledMidi> scheduled = [];
  final List<List<int>> sent = [];

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
  void send(List<int> midi) => sent.add(midi);
  @override
  void schedule(List<ScheduledMidi> events) => scheduled.addAll(events);
  @override
  void clearScheduled() {}
  @override
  void allNotesOff() {}
  @override
  Future<void> dispose() async {}
}

class FakeMidiInput implements MidiInputService {
  final StreamController<PlayedNote> _notes =
      StreamController<PlayedNote>.broadcast();
  final StreamController<int> _sustain = StreamController<int>.broadcast();
  final ValueNotifier<Set<int>> _held = ValueNotifier(const {});

  @override
  Stream<PlayedNote> get notes => _notes.stream;
  @override
  Stream<int> get sustain => _sustain.stream;
  @override
  ValueListenable<Set<int>> get held => _held;

  void press(int pitch, {double atSeconds = 0, int velocity = 80}) {
    _notes.add(
      PlayedNote(
        pitch: pitch,
        velocity: velocity,
        channel: 0,
        on: true,
        atSeconds: atSeconds,
      ),
    );
  }

  void release(int pitch, {double atSeconds = 0}) {
    _notes.add(
      PlayedNote(
        pitch: pitch,
        velocity: 0,
        channel: 0,
        on: false,
        atSeconds: atSeconds,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_notes.close());
    unawaited(_sustain.close());
    _held.dispose();
  }
}

PerformanceTrack _loadTrack(String fixture) {
  final bytes = File('test/fixtures/$fixture').readAsBytesSync();
  return PerformanceTrack.fromDocument(
    VsbDocument.fromBytes(Uint8List.fromList(bytes)),
  );
}

VsbDocument _loadDoc(String fixture) {
  final bytes = File('test/fixtures/$fixture').readAsBytesSync();
  return VsbDocument.fromBytes(Uint8List.fromList(bytes));
}

void _advanceUntil(
  FakeSoundEngine engine,
  ScoreAudioScheduler scheduler,
  double targetMs,
) {
  var guard = 0;
  while (scheduler.positionMs < targetMs) {
    engine.now += 0.025;
    scheduler.pump();
    guard++;
    if (guard > 200000) {
      throw StateError('_advanceUntil não convergiu para $targetMs ms');
    }
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PracticeController', () {
    test('tempo real: notas no tempo viram certas, o que não foi tocado vira '
        'perdido e o resumo reflete', () async {
      final track = _loadTrack('erik-satie.vsb');
      final doc = _loadDoc('erik-satie.vsb');
      final timeline = ScoreTimeline(doc);
      final engine = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);
      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
        mode: PracticeMode.realtime,
        measureIndexAt: timeline.measureIndexAt,
      );
      addTearDown(practice.dispose);

      final mine = track.events
          .where(
            (e) => Hand.direita.studentStaves.contains(e.staff) && !e.ornament,
          )
          .toList();
      practice.start();
      // Toca as 4 primeiras no tempo, 1 errada (pitch fora), pula as demais.
      for (final e in mine.take(4)) {
        _advanceUntil(engine, scheduler, e.onMs);
        midi.press(e.pitch, atSeconds: engine.now);
        await pumpEventQueue();
      }
      midi.press(1, atSeconds: engine.now);
      await pumpEventQueue();
      final until = mine[8].onMs + 400;
      _advanceUntil(engine, scheduler, until);
      // Dispara o tick manual (autoTick do controller é Timer real).
      practice.finish();
      final r = practice.report;
      expect(r.correct, 4);
      expect(r.wrong, 1);
      expect(r.missed, greaterThanOrEqualTo(3));
      expect(practice.hasVerdicts, isTrue);
      practice.stop();
    });

    test('ritmo: qualquer tecla no tempo do onset vira certa, soa as notas '
        'esperadas e o resto vira perdido', () async {
      final track = _loadTrack('erik-satie.vsb');
      final doc = _loadDoc('erik-satie.vsb');
      final engine = FakeSoundEngine();
      final magic = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);
      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
        mode: PracticeMode.rhythm,
        magicEngine: magic,
      );
      addTearDown(practice.dispose);

      final onsets =
          (track.events
              .where(
                (e) =>
                    Hand.direita.studentStaves.contains(e.staff) && !e.ornament,
              )
              .map((e) => e.onMs)
              .toSet()
              .toList()
            ..sort());
      practice.start();
      for (final ms in onsets.take(4)) {
        _advanceUntil(engine, scheduler, ms);
        midi.press(1, atSeconds: engine.now); // pitch irrelevante
        await pumpEventQueue();
        midi.release(1, atSeconds: engine.now + 0.01);
        await pumpEventQueue();
      }
      _advanceUntil(engine, scheduler, onsets[8] + 400);
      practice.finish();
      final r = practice.report;
      expect(r.correct + r.early + r.late, 4);
      expect(r.extra, 0);
      expect(r.missed, greaterThanOrEqualTo(3));
      // Piano mágico: note-on de notas esperadas (não o pitch 1) e note-off.
      final ons = magic.sent.where((m) => (m[0] & 0xF0) == 0x90);
      expect(ons, isNotEmpty);
      expect(ons.every((m) => m[1] != 1), isTrue);
      expect(magic.sent.where((m) => (m[0] & 0xF0) == 0x80), isNotEmpty);
      practice.stop();
    });

    test('loop A-B: ao concluir o último passo do trecho a sessão recomeça '
        'no início e avisa o host', () async {
      final track = _loadTrack('erik-satie.vsb');
      final doc = _loadDoc('erik-satie.vsb');
      final measures = ScoreTimeline(doc).measures;
      final startMs = measures[1].startMs.toDouble();
      final endMs = measures[1].endMs.toDouble();
      final engine = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);
      final restarts = <double>[];
      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
        onLoopRestart: restarts.add,
      );
      addTearDown(practice.dispose);

      practice.start(fromMs: startMs);
      practice.setLoop(startMs, endMs);
      final first = practice.currentStep.value!;
      expect(first.onMs, greaterThanOrEqualTo(startMs));

      // Toca todos os passos do trecho.
      var guard = 0;
      while (restarts.isEmpty && guard++ < 50) {
        final step = practice.currentStep.value!;
        _advanceUntil(engine, scheduler, step.onMs);
        for (final e in step.notes) {
          midi.press(e.pitch, atSeconds: engine.now);
        }
        await pumpEventQueue();
      }
      expect(restarts, [startMs]);
      expect(practice.currentStep.value!.onMs, first.onMs);
      expect(scheduler.positionMs, closeTo(startMs, 1));
    });

    test(
      'nota certa avança o freio e o passo, e pinta a nota de verde',
      () async {
        final track = _loadTrack('maple-leaf-rag.vsb');
        final doc = _loadDoc('maple-leaf-rag.vsb');
        final engine = FakeSoundEngine();
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final scoreController = ScoreController(document: doc);
        addTearDown(scoreController.dispose);
        addTearDown(scoreController.clearAll);
        final midi = FakeMidiInput();
        addTearDown(midi.dispose);

        final practice = PracticeController(
          midiInput: midi,
          track: track,
          scheduler: scheduler,
          controller: scoreController,
          hand: Hand.direita, // aluno = pauta 1, app = pauta 2
        );
        addTearDown(practice.dispose);

        practice.start();
        final step0 = practice.currentStep.value!;
        _advanceUntil(engine, scheduler, step0.onMs);
        expect(scheduler.positionMs, step0.onMs);

        for (final e in step0.notes) {
          midi.press(e.pitch, atSeconds: engine.now);
        }
        // `MidiInputService.notes` é um broadcast normal (sem `sync: true`,
        // como o de verdade em FlutterMidiInputService): a entrega é por
        // microtask, não imediata — precisa esvaziar a fila antes de conferir.
        await pumpEventQueue();

        // Todas as notas do passo tocadas certas: sessão avançou.
        final step1 = practice.currentStep.value;
        expect(step1, isNot(same(step0)));
        expect(
          step1 == null || step1.onMs >= step0.onMs,
          isTrue,
          reason: 'o próximo passo não pode voltar no tempo',
        );

        // Cada nota do passo concluído está pintada de verde agora mesmo
        // (attack/hold nulos — a cor aparece na hora, sem precisar de tick).
        for (final e in step0.notes) {
          expect(
            scoreController.colorOf(e.id),
            kPracticeCorrectColor,
            reason: 'nota ${e.id} deveria estar verde após acerto',
          );
        }

        // O freio avançou: uma vez que o relógio alcance o novo passo (ou o
        // fim, se a peça acabou), a posição não fica presa no passo antigo.
        if (step1 != null) {
          _advanceUntil(engine, scheduler, step1.onMs);
          expect(scheduler.positionMs, step1.onMs);
        }
      },
    );

    test('tecla errada vira fantasma na coluna do passo; certa não', () async {
      final track = _loadTrack('satie-fantasma.vsb');
      final doc = _loadDoc('satie-fantasma.vsb');
      final engine = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      final ghosts = GhostController()..attachDocument(doc);
      addTearDown(ghosts.dispose);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);

      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
        ghosts: ghosts,
      );
      addTearDown(practice.dispose);
      practice.start();
      final step = practice.currentStep.value!;
      final wrong =
          step.notes.map((e) => e.pitch).reduce((a, b) => a > b ? a : b) + 1;
      final stepIds = step.notes.map((e) => e.id).toSet();

      midi.press(wrong, atSeconds: engine.now);
      await pumpEventQueue();
      expect(ghosts.visible, hasLength(1));
      final ghost = ghosts.visible.single.ghost;
      expect(ghost.key, wrong);
      expect(stepIds.map(doc.sceneIdOf), contains(ghost.targetId));

      // Tecla certa não gera fantasma nova.
      midi.press(step.notes.first.pitch, atSeconds: engine.now);
      await pumpEventQueue();
      expect(ghosts.visible, hasLength(1));

      practice.stop();
      expect(ghosts.isEmpty, isTrue);
    });

    test('nota errada não avança o passo, pisca a mais próxima e marca a '
        'tecla física', () async {
      final track = _loadTrack('maple-leaf-rag.vsb');
      final doc = _loadDoc('maple-leaf-rag.vsb');
      final engine = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);

      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
      );
      addTearDown(practice.dispose);

      practice.start();
      final step0 = practice.currentStep.value!;
      _advanceUntil(engine, scheduler, step0.onMs);

      // Pitch bem fora do range de piano: garantidamente não é nenhuma
      // nota esperada do passo.
      const wrongPitch = 200;
      midi.press(wrongPitch, atSeconds: engine.now);
      await pumpEventQueue();

      expect(
        practice.currentStep.value,
        same(step0),
        reason: 'nota errada não avança o passo',
      );
      expect(practice.wrongPitches.value, contains(wrongPitch));

      final nearest = step0.notes.reduce(
        (a, b) => (a.pitch - wrongPitch).abs() <= (b.pitch - wrongPitch).abs()
            ? a
            : b,
      );
      expect(scoreController.isHighlighted(nearest.id), isTrue);

      midi.release(wrongPitch, atSeconds: engine.now);
      await pumpEventQueue();
      expect(practice.wrongPitches.value, isNot(contains(wrongPitch)));
    });

    test('stop() solta o freio e limpa os destaques', () async {
      final track = _loadTrack('maple-leaf-rag.vsb');
      final doc = _loadDoc('maple-leaf-rag.vsb');
      final engine = FakeSoundEngine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: doc);
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = FakeMidiInput();
      addTearDown(midi.dispose);

      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.esquerda,
      );
      addTearDown(practice.dispose);

      practice.start();
      expect(scheduler.isRunning, isTrue);
      practice.stop();
      expect(scheduler.isRunning, isFalse);

      // Sem freio: pump() volta a agendar livremente (comportamento normal
      // de playback), sem ficar preso num onMs antigo.
      scheduler.play(scheduler.positionMs);
      _advanceUntil(engine, scheduler, track.durationMs);
      engine.now += 1.0;
      scheduler.pump();
      final noteOns = engine.scheduled
          .where((m) => m.status & 0xF0 == 0x90)
          .length;
      expect(noteOns, track.events.length);
    });
  });
}

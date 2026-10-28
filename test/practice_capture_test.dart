// EX07: o PracticeController grava a execução (`capture`) e casa as notas
// certas com a escrita (`matches`). Com o MIDI falso, a hora gravada é a
// mesma que a conferência do tempo real usou, e o pedal entra na gravação
// com a hora musical. Pausado, não grava nada.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_comum/practice/hand.dart';
import 'package:zywny_comum/practice/practice_controller.dart';

import 'support/practice_fakes.dart';

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

  group('PracticeController e a gravação', () {
    test('a tecla certa vira gravação e par, na hora que a conferência usa; '
        'o fim e o pedal também entram', () async {
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

      final first = track.events.firstWhere(
        (e) => Hand.direita.studentStaves.contains(e.staff) && !e.ornament,
      );
      practice.start();
      _advanceUntil(engine, scheduler, first.onMs);
      midi.press(first.pitch, atSeconds: engine.now, velocity: 90);
      await pumpEventQueue();
      midi.release(first.pitch, atSeconds: engine.now + 0.3);
      await pumpEventQueue();
      final pedalMs = scheduler.musicalAtDevice(engine.now);
      midi.pedal(127, atSeconds: engine.now);
      await pumpEventQueue();

      expect(practice.report.correct, 1);
      final played = practice.capture.notes.single;
      expect(played.pitch, first.pitch);
      expect(played.velocity, 90);
      expect(played.offMs, isNotNull);
      expect(played.offMs! - played.onMs, closeTo(300, 1));

      final match = practice.matches.single;
      expect(match.written.id, first.id);
      expect(match.played, played);
      expect(
        practice.report.meanDeltaMs,
        closeTo(match.played.onMs - first.onMs, 0.001),
      );

      final pedal = practice.capture.pedals.single;
      expect(pedal.down, isTrue);
      expect(pedal.atMs, closeTo(pedalMs, 0.001));
      practice.stop();
    });

    test('pausado, as teclas e o pedal não entram na gravação', () async {
      final track = _loadTrack('erik-satie.vsb');
      final doc = _loadDoc('erik-satie.vsb');
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
      );
      addTearDown(practice.dispose);

      practice.start();
      practice.pause();
      midi.press(60, atSeconds: engine.now);
      midi.pedal(127, atSeconds: engine.now);
      await pumpEventQueue();

      expect(practice.capture.notes, isEmpty);
      expect(practice.capture.pedals, isEmpty);
      expect(practice.matches, isEmpty);
      practice.stop();
    });
  });
}

// Q05 — As alturas no app: o casador compara a altura **escrita**; o agendador
// e o monitor tocam a **soada** (ou o que o teclado MIDI lê); o teclado
// transpõe ou não o que manda e o que recebe, e isso fica guardado por
// teclado.
//
// A partitura de teste é uma gravura de verdade sem transposição (como o
// `midi.json` de uma gravada com `-m3` seria): suas alturas fazem o papel da
// escrita, e o `PitchFrame` com `k = −3` faz o resto.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/audio/score_audio_scheduler.dart';
import 'package:zywny/audio/sound_engine.dart';
import 'package:zywny/midi/midi_input_service.dart';
import 'package:zywny/midi/midi_monitor.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/music/pitch_frame.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_controller.dart';
import 'package:zywny/settings/app_settings.dart';

class _Engine implements SoundEngine {
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

class _Input implements MidiInputService {
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

  void note(int pitch, {required bool on, double atSeconds = 0}) => _notes.add(
    PlayedNote(
      pitch: pitch,
      velocity: on ? 80 : 0,
      channel: 0,
      on: on,
      atSeconds: atSeconds,
    ),
  );

  @override
  void dispose() {
    unawaited(_notes.close());
    unawaited(_sustain.close());
    _held.dispose();
  }
}

VsbDocument _doc() => VsbDocument.fromBytes(
  Uint8List.fromList(File('test/fixtures/erik-satie.vsb').readAsBytesSync()),
);

void _advanceUntil(_Engine engine, ScoreAudioScheduler scheduler, double ms) {
  var guard = 0;
  while (scheduler.positionMs < ms) {
    engine.now += 0.025;
    scheduler.pump();
    if (guard++ > 200000) throw StateError('não convergiu para $ms ms');
  }
}

/// Mi♭ → Dó: a partitura desce uma terça menor, `k = −3` (o teclado em +3).
const int _k = -3;

/// Um teclado que não transpõe o MIDI que manda (a recebida é a escrita) e um
/// que transpõe (a recebida é a soada).
const _plain = PitchFrame(_k);
const _shifting = PitchFrame(_k, keyboardShiftsOut: true);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('casador: recebe a escrita, qualquer que seja o teclado', () {
    // O número que o teclado manda ao ser apertada a tecla de altura escrita
    // [written]: o mesmo (teclado que não transpõe) ou a soada (que transpõe).
    int sent(PitchFrame frame, int written) =>
        frame.keyboardShiftsOut ? written - frame.k : written;

    for (final (name, frame) in [
      ('teclado que não transpõe a saída', _plain),
      ('teclado que transpõe a saída', _shifting),
    ]) {
      test('modo espera, $name', () async {
        final track = PerformanceTrack.fromDocument(_doc());
        final engine = _Engine();
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final scoreController = ScoreController(document: _doc());
        addTearDown(scoreController.dispose);
        addTearDown(scoreController.clearAll);
        final midi = _Input();
        addTearDown(midi.dispose);
        final practice = PracticeController(
          midiInput: midi,
          track: track,
          scheduler: scheduler,
          controller: scoreController,
          hand: Hand.direita,
          writtenFromReceived: frame.writtenFromReceived,
        );
        addTearDown(practice.dispose);

        practice.start();
        for (var i = 0; i < 6; i++) {
          final step = practice.currentStep.value!;
          _advanceUntil(engine, scheduler, step.onMs);
          for (final e in step.notes) {
            midi.note(sent(frame, e.pitch), on: true, atSeconds: engine.now);
          }
          await pumpEventQueue();
          for (final e in step.notes) {
            midi.note(sent(frame, e.pitch), on: false, atSeconds: engine.now);
          }
          await pumpEventQueue();
        }
        practice.finish();
        expect(practice.report.wrong, 0);
        expect(practice.report.correct, greaterThanOrEqualTo(6));
        expect(practice.wrongPitches.value, isEmpty);
        practice.stop();
      });

      test('tempo real, $name', () async {
        final track = PerformanceTrack.fromDocument(_doc());
        final engine = _Engine();
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final scoreController = ScoreController(document: _doc());
        addTearDown(scoreController.dispose);
        addTearDown(scoreController.clearAll);
        final midi = _Input();
        addTearDown(midi.dispose);
        final practice = PracticeController(
          midiInput: midi,
          track: track,
          scheduler: scheduler,
          controller: scoreController,
          hand: Hand.direita,
          mode: PracticeMode.realtime,
          writtenFromReceived: frame.writtenFromReceived,
        );
        addTearDown(practice.dispose);

        final mine = track.events
            .where(
              (e) =>
                  Hand.direita.studentStaves.contains(e.staff) && !e.ornament,
            )
            .toList();
        practice.start();
        for (final e in mine.take(4)) {
          _advanceUntil(engine, scheduler, e.onMs);
          midi.note(sent(frame, e.pitch), on: true, atSeconds: engine.now);
          await pumpEventQueue();
        }
        practice.finish();
        expect(practice.report.correct, 4);
        expect(practice.report.wrong, 0);
        practice.stop();
      });
    }

    test('a escrita na soada não passa: a tecla errada continua errada', () async {
      // Teclado que não transpõe (recebida = escrita): a soada seria 3 acima —
      // tocar a soada é tocar a tecla errada da partitura transposta.
      final track = PerformanceTrack.fromDocument(_doc());
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final scoreController = ScoreController(document: _doc());
      addTearDown(scoreController.dispose);
      addTearDown(scoreController.clearAll);
      final midi = _Input();
      addTearDown(midi.dispose);
      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: scoreController,
        hand: Hand.direita,
        writtenFromReceived: _plain.writtenFromReceived,
      );
      addTearDown(practice.dispose);

      practice.start();
      final step = practice.currentStep.value!;
      _advanceUntil(engine, scheduler, step.onMs);
      final inStep = {for (final e in step.notes) e.pitch};
      // A soada das notas do passo, que não é nenhuma delas.
      final soundings = [
        for (final e in step.notes)
          if (!inStep.contains(e.pitch - _k)) e.pitch - _k,
      ];
      expect(soundings, isNotEmpty, reason: 'passo sem tecla vizinha livre');
      midi.note(soundings.first, on: true, atSeconds: engine.now);
      await pumpEventQueue();
      expect(practice.currentStep.value, same(step));
      // A tecla errada na tela é a que a pessoa apertou (escrita).
      expect(practice.wrongPitches.value, contains(soundings.first));
    });

    test(
      'sem a função, o casador compara o que chega (o caminho de sempre)',
      () async {
        final track = PerformanceTrack.fromDocument(_doc());
        final engine = _Engine();
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final scoreController = ScoreController(document: _doc());
        addTearDown(scoreController.dispose);
        addTearDown(scoreController.clearAll);
        final midi = _Input();
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
        final step = practice.currentStep.value!;
        _advanceUntil(engine, scheduler, step.onMs);
        for (final e in step.notes) {
          midi.note(e.pitch, on: true, atSeconds: engine.now);
        }
        await pumpEventQueue();
        expect(practice.currentStep.value, isNot(same(step)));
      },
    );
  });

  group('agendador: o motor recebe a altura que toca', () {
    Set<int> pitchesOnScheduled(_Engine engine) => {
      for (final m in engine.scheduled)
        if (m.status & 0xF0 == 0x90 && m.status & 0x0F != 0x09) m.d1,
    };

    _Engine playAll(int Function(int)? pitchOf) {
      final track = PerformanceTrack.fromDocument(_doc());
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      if (pitchOf != null) scheduler.pitchOf = pitchOf;
      scheduler.play(0);
      _advanceUntil(engine, scheduler, track.durationMs);
      engine.now += 1;
      scheduler.pump();
      return engine;
    }

    test('sem transposição, o pitch é o da partitura', () {
      final track = PerformanceTrack.fromDocument(_doc());
      final engine = playAll(null);
      expect(pitchesOnScheduled(engine), {
        for (final e in track.events) e.pitch,
      });
    });

    test('com -m3 o motor do app recebe a escrita + 3 (a soada)', () {
      final track = PerformanceTrack.fromDocument(_doc());
      final engine = playAll(
        (w) => _plain.engineFromWritten(w, midiKeyboard: false),
      );
      expect(pitchesOnScheduled(engine), {
        for (final e in track.events) e.pitch + 3,
      });
      // E o note-off é da mesma nota que o note-on.
      final ons = engine.scheduled.where((m) => m.status & 0xF0 == 0x90).length;
      final offs = engine.scheduled
          .where((m) => m.status & 0xF0 == 0x80)
          .length;
      expect(offs, ons);
      final offPitches = {
        for (final m in engine.scheduled)
          if (m.status & 0xF0 == 0x80 && m.status & 0x0F != 0x09) m.d1,
      };
      expect(offPitches, pitchesOnScheduled(engine));
    });

    test(
      'teclado MIDI que transpõe o que recebe (in: true) recebe a escrita',
      () {
        final track = PerformanceTrack.fromDocument(_doc());
        const frame = PitchFrame(_k, keyboardShiftsIn: true);
        final engine = playAll(
          (w) => frame.engineFromWritten(w, midiKeyboard: true),
        );
        expect(pitchesOnScheduled(engine), {
          for (final e in track.events) e.pitch,
        });
      },
    );

    test(
      'teclado MIDI que não transpõe o que recebe (in: false) recebe a soada',
      () {
        final track = PerformanceTrack.fromDocument(_doc());
        final engine = playAll(
          (w) => _plain.engineFromWritten(w, midiKeyboard: true),
        );
        expect(pitchesOnScheduled(engine), {
          for (final e in track.events) e.pitch + 3,
        });
      },
    );

    test('som do app: nada a fazer no teclado, manda a soada ao teclado', () {
      const app = PitchFrame(_k, keyboardShiftsIn: true, appIsSound: true);
      expect(app.outFromWritten(60), 63);
      expect(app.writtenFromReceived(60), 60);
    });
  });

  group('monitor: toca a soada da tecla apertada', () {
    test('teclado que não transpõe a saída: Dó (60) soa Mi♭ (63)', () async {
      final engine = _Engine();
      final midi = _Input();
      addTearDown(midi.dispose);
      final monitor = MidiMonitor(
        input: midi,
        engine: engine,
        pitchOf: (r) => _plain.engineFromReceived(r, midiKeyboard: false),
      );
      addTearDown(monitor.dispose);
      midi.note(60, on: true);
      midi.note(60, on: false);
      await pumpEventQueue();
      // O primeiro é o Program Change do canal do monitor.
      expect(engine.sent.skip(1).map((m) => [m[0] & 0xF0, m[1]]), [
        [0x90, 63],
        [0x80, 63],
      ]);
    });

    test(
      'teclado que transpõe a saída: já chega 63, soa 63 (sem somar 2x)',
      () async {
        final engine = _Engine();
        final midi = _Input();
        addTearDown(midi.dispose);
        final monitor = MidiMonitor(
          input: midi,
          engine: engine,
          pitchOf: (r) => _shifting.engineFromReceived(r, midiKeyboard: false),
        );
        addTearDown(monitor.dispose);
        midi.note(63, on: true);
        midi.note(63, on: false);
        await pumpEventQueue();
        expect(engine.sent.skip(1).map((m) => [m[0] & 0xF0, m[1]]), [
          [0x90, 63],
          [0x80, 63],
        ]);
      },
    );

    test(
      'o note-off sai na mesma altura do note-on, mesmo se o tom mudar',
      () async {
        final engine = _Engine();
        final midi = _Input();
        addTearDown(midi.dispose);
        var frame = _plain;
        final monitor = MidiMonitor(
          input: midi,
          engine: engine,
          pitchOf: (r) => frame.engineFromReceived(r, midiKeyboard: false),
        );
        addTearDown(monitor.dispose);
        midi.note(60, on: true);
        await pumpEventQueue();
        frame = PitchFrame.identity; // a pessoa desligou a transposição
        midi.note(60, on: false);
        await pumpEventQueue();
        expect(engine.sent.skip(1).map((m) => [m[0] & 0xF0, m[1]]), [
          [0x90, 63],
          [0x80, 63], // não 60: a nota que ligou é a que desliga
        ]);
      },
    );

    test('sem transposição, o monitor manda o que chega', () async {
      final engine = _Engine();
      final midi = _Input();
      addTearDown(midi.dispose);
      final monitor = MidiMonitor(input: midi, engine: engine);
      addTearDown(monitor.dispose);
      midi.note(60, on: true);
      await pumpEventQueue();
      expect(engine.sent.last[1], 60);
    });
  });

  group('comportamento do teclado, guardado por dispositivo', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test(
      'teclado não conferido: desconhecido (o app supõe que não transpõe)',
      () {
        final settings = AppSettings(prefs: SharedPreferencesAsync());
        expect(
          settings.keyboardTransposeOf('Yamaha P-45'),
          KeyboardTransposeBehavior.unknown,
        );
        expect(settings.keyboardTransposeOf(null).shiftsOut, isNull);
      },
    );

    test('guarda por nome e relê', () async {
      final prefs = SharedPreferencesAsync();
      final settings = AppSettings(prefs: prefs);
      settings.setKeyboardTranspose(
        'Yamaha P-45',
        const KeyboardTransposeBehavior(shiftsOut: true, shiftsIn: false),
      );
      settings.setKeyboardTranspose(
        'Casio CT-S1',
        const KeyboardTransposeBehavior(shiftsOut: false),
      );
      await Future<void>.delayed(Duration.zero);

      final again = AppSettings(prefs: prefs);
      await again.load();
      expect(
        again.keyboardTransposeOf('Yamaha P-45'),
        const KeyboardTransposeBehavior(shiftsOut: true, shiftsIn: false),
      );
      expect(again.keyboardTransposeOf('Casio CT-S1').shiftsOut, isFalse);
      expect(again.keyboardTransposeOf('Casio CT-S1').shiftsIn, isNull);
      expect(
        again.keyboardTransposeOf('Outro'),
        KeyboardTransposeBehavior.unknown,
      );
    });

    test('valor estragado vale o padrão', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('midi_keyboard_transpose', '{"x": 3, ');
      final settings = AppSettings(prefs: prefs);
      await settings.load();
      expect(
        settings.keyboardTransposeOf('x'),
        KeyboardTransposeBehavior.unknown,
      );
    });
  });
}

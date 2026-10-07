import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_midi/midi_input_service.dart';

/// Motor de som falso: o relógio é `now`, que o teste anda à mão.
class FakeSoundEngine implements SoundEngine {
  double now = 0;
  final List<ScheduledMidi> scheduled = [];
  final List<List<int>> sent = [];
  int allNotesOffCalls = 0;

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
  void allNotesOff() {
    allNotesOffCalls++;
  }

  @override
  Future<void> dispose() async {}
}

/// Teclado MIDI falso: `press`/`release` entram no stream de notas, que é um
/// broadcast comum (esvazie com `pumpEventQueue`).
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

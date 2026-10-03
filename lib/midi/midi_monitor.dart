import 'dart:async';

import '../audio/sound_engine.dart';
import 'midi_input_service.dart';

/// Canal MIDI reservado para o monitor (M02): programa piano, separado do
/// canal que `ScoreAudioScheduler` usa para a partitura (K04) — os dois
/// nunca disputam o mesmo canal no sintetizador.
const int kMidiMonitorChannel = 15;

/// Liga [MidiInputService] a um [SoundEngine]: o que o usuário toca sai
/// pelo sintetizador do app, para teclados controladores sem som próprio
/// (M02). `send` direto ao chegar, sem agendar — diferente do agendador da
/// partitura, que sempre agenda no futuro.
class MidiMonitor {
  MidiMonitor({required MidiInputService input, required SoundEngine engine})
    : _input = input, // ignore: prefer_initializing_formals
      // ignore: prefer_initializing_formals
      _engine = engine {
    _engine.send([0xC0 | kMidiMonitorChannel, 0, 0]);
    _notesSub = _input.notes.listen(_onNote);
    _sustainSub = _input.sustain.listen(_onSustain);
  }

  final MidiInputService _input;
  final SoundEngine _engine;
  late final StreamSubscription<PlayedNote> _notesSub;
  late final StreamSubscription<int> _sustainSub;

  void _onNote(PlayedNote note) {
    _engine.send([
      (note.on ? 0x90 : 0x80) | kMidiMonitorChannel,
      note.pitch,
      note.on ? note.velocity : 0,
    ]);
  }

  void _onSustain(int value) {
    _engine.send([0xB0 | kMidiMonitorChannel, 64, value]);
  }

  /// Note-off para tudo que [MidiInputService.held] ainda lista retido —
  /// chamado ao desligar a opção e ao trocar/desconectar o dispositivo
  /// (evita nota presa; docs/plano/M02-monitor-pelo-sintetizador.md).
  void allNotesOff() {
    for (final pitch in _input.held.value) {
      _engine.send([0x80 | kMidiMonitorChannel, pitch, 0]);
    }
  }

  void dispose() {
    allNotesOff();
    unawaited(_notesSub.cancel());
    unawaited(_sustainSub.cancel());
  }
}

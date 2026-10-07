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
  MidiMonitor({
    required MidiInputService input,
    required SoundEngine engine,
    this.pitchOf = _samePitch,
  }) : _input = input, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _engine = engine {
    _engine.send([0xC0 | kMidiMonitorChannel, 0, 0]);
    _notesSub = _input.notes.listen(_onNote);
    _sustainSub = _input.sustain.listen(_onSustain);
  }

  final MidiInputService _input;
  final SoundEngine _engine;

  /// A altura a mandar ao motor para a nota que chegou do teclado (fase Q,
  /// `PitchFrame.monitorFromReceived`): com a música transposta, o monitor
  /// toca a **soada**. Sem transposição, a mesma.
  final int Function(int received) pitchOf;

  static int _samePitch(int pitch) => pitch;

  late final StreamSubscription<PlayedNote> _notesSub;
  late final StreamSubscription<int> _sustainSub;

  /// Altura mandada ao motor por nota ligada ainda não desligada: o desligar
  /// usa a mesma, mesmo que a transposição mude no meio da nota.
  final Map<int, int> _sounding = {};

  void _onNote(PlayedNote note) {
    final int pitch;
    if (note.on) {
      pitch = pitchOf(note.pitch);
      _sounding[note.pitch] = pitch;
    } else {
      pitch = _sounding.remove(note.pitch) ?? pitchOf(note.pitch);
    }
    _engine.send([
      (note.on ? 0x90 : 0x80) | kMidiMonitorChannel,
      pitch,
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
      _engine.send([
        0x80 | kMidiMonitorChannel,
        _sounding.remove(pitch) ?? pitchOf(pitch),
        0,
      ]);
    }
    _sounding.clear();
  }

  void dispose() {
    allNotesOff();
    unawaited(_notesSub.cancel());
    unawaited(_sustainSub.cancel());
  }
}

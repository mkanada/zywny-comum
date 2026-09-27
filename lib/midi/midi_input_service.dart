import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';

/// Uma nota recebida de um teclado MIDI (M01).
///
/// `atSeconds` é o relógio do app na chegada — nunca `event.timestamp` do
/// plugin, cuja unidade varia por plataforma (ver
/// `docs/plano/M01-entrada-midi.md`).
@immutable
class PlayedNote {
  const PlayedNote({
    required this.pitch,
    required this.velocity,
    required this.channel,
    required this.on,
    required this.atSeconds,
  });

  final int pitch;
  final int velocity;
  final int channel;
  final bool on;
  final double atSeconds;

  @override
  String toString() =>
      'PlayedNote(${on ? "on" : "off"} $pitch vel=$velocity ch=$channel '
      '@${atSeconds.toStringAsFixed(3)}s)';
}

/// Interface única para "quem publica notas tocadas por um teclado MIDI"
/// (M01) — `lib/main.dart` e o painel de monitor dependem só disto, nunca de
/// `flutter_midi_command` direto.
abstract class MidiInputService {
  Stream<PlayedNote> get notes;

  /// CC64 (pedal de sustain), valor cru 0..127.
  Stream<int> get sustain;

  /// Pitches apertados agora, para o teclado desenhado do monitor.
  ValueListenable<Set<int>> get held;

  void dispose();
}

/// Implementação sobre `flutter_midi_command` (D-MIDI). Converte
/// [MidiDataReceivedEvent] em [PlayedNote]/sustain/`held`.
///
/// [events] é injetável para teste — sem ele, escuta
/// `MidiCommand().onMidiDataReceived`, que abre um canal de plataforma
/// (inexistente em `flutter test`).
class FlutterMidiInputService implements MidiInputService {
  FlutterMidiInputService({
    required double Function() nowSeconds,
    Stream<MidiDataReceivedEvent>? events,
  }) : _nowSeconds = nowSeconds { // ignore: prefer_initializing_formals
    _sub = (events ?? MidiCommand().onMidiDataReceived)?.listen(_onEvent);
  }

  final double Function() _nowSeconds;
  StreamSubscription<MidiDataReceivedEvent>? _sub;
  final StreamController<PlayedNote> _notes =
      StreamController<PlayedNote>.broadcast();
  final StreamController<int> _sustain = StreamController<int>.broadcast();
  final ValueNotifier<Set<int>> _held = ValueNotifier(const <int>{});

  @override
  Stream<PlayedNote> get notes => _notes.stream;

  @override
  Stream<int> get sustain => _sustain.stream;

  @override
  ValueListenable<Set<int>> get held => _held;

  void _onEvent(MidiDataReceivedEvent event) =>
      handleMessage(event.message, atSeconds: _nowSeconds());

  /// Exposto para os testes de unidade do M01 (parsing/normalização com
  /// mensagens sintéticas): não depende de um `MidiCommand` de verdade.
  @visibleForTesting
  void handleMessage(MidiMessage message, {required double atSeconds}) {
    switch (message) {
      case NoteOnMessage(:final channel, :final note, :final velocity):
        // O parser do plugin já troca note-on com velocity 0 por
        // NoteOffMessage, mas o serviço normaliza de novo por conta própria
        // (running status de muitos teclados; docs/plano/M01-entrada-midi.md)
        // — não depende de um detalhe de implementação de terceiros.
        _emitNote(
          pitch: note,
          velocity: velocity,
          channel: channel,
          on: velocity > 0,
          atSeconds: atSeconds,
        );
      case NoteOffMessage(:final channel, :final note, :final velocity):
        _emitNote(
          pitch: note,
          velocity: velocity,
          channel: channel,
          on: false,
          atSeconds: atSeconds,
        );
      case CCMessage(:final controller, :final value) when controller == 64:
        _sustain.add(value);
      default:
        break;
    }
  }

  void _emitNote({
    required int pitch,
    required int velocity,
    required int channel,
    required bool on,
    required double atSeconds,
  }) {
    _notes.add(
      PlayedNote(
        pitch: pitch,
        velocity: velocity,
        channel: channel,
        on: on,
        atSeconds: atSeconds,
      ),
    );
    final next = Set<int>.of(_held.value);
    if (on) {
      next.add(pitch);
    } else {
      next.remove(pitch);
    }
    _held.value = next;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_notes.close());
    unawaited(_sustain.close());
    _held.dispose();
  }
}

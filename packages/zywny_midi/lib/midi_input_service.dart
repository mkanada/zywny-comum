// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';

import 'package:zywny_diag/diag_log.dart';

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

/// Um movimento do pedal de sustain (CC64): o valor cru (0..127) e a hora de
/// chegada, no mesmo relógio de [PlayedNote.atSeconds] (EX07: a gravação da
/// execução precisa dela).
@immutable
class SustainChange {
  const SustainChange({required this.value, required this.atSeconds});

  final int value;
  final double atSeconds;

  @override
  String toString() =>
      'SustainChange($value @${atSeconds.toStringAsFixed(3)}s)';
}

/// Interface única para "quem publica notas tocadas por um teclado MIDI"
/// (M01) — `lib/main.dart` e o painel de monitor dependem só disto, nunca de
/// `flutter_midi_command` direto.
abstract class MidiInputService {
  Stream<PlayedNote> get notes;

  /// CC64 (pedal de sustain), com o valor cru 0..127 e a hora.
  Stream<SustainChange> get sustain;

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
///
/// [resubscribeOn] refaz a assinatura a cada evento do stream. O plugin monta
/// `onMidiDataReceived` na hora em que o getter é lido, com os transportes
/// que existem então: um serviço criado antes de o transporte Bluetooth ser
/// instalado nunca ouviria um teclado BLE (o USB, sim). Quem tem um
/// `MidiDeviceManager` passa `manager.transportInstalled`.
class FlutterMidiInputService implements MidiInputService {
  FlutterMidiInputService({
    required double Function() nowSeconds,
    Stream<MidiDataReceivedEvent>? events,
    @visibleForTesting Stream<MidiDataReceivedEvent>? Function()? eventsSource,
    Stream<void>? resubscribeOn,
  }) : _nowSeconds = nowSeconds,
       _eventsSource =
           eventsSource ??
           (events != null
               ? () => events
               : () => MidiCommand().onMidiDataReceived) {
    _subscribe();
    _resubscribeSub = resubscribeOn?.listen((_) => _subscribe());
  }

  final Stream<MidiDataReceivedEvent>? Function() _eventsSource;
  StreamSubscription<void>? _resubscribeSub;

  void _subscribe() {
    unawaited(_sub?.cancel());
    _sub = _eventsSource()?.listen(_onEvent);
  }

  final double Function() _nowSeconds;
  StreamSubscription<MidiDataReceivedEvent>? _sub;
  final StreamController<PlayedNote> _notes =
      StreamController<PlayedNote>.broadcast();
  final StreamController<SustainChange> _sustain =
      StreamController<SustainChange>.broadcast();
  final ValueNotifier<Set<int>> _held = ValueNotifier(const <int>{});

  @override
  Stream<PlayedNote> get notes => _notes.stream;

  @override
  Stream<SustainChange> get sustain => _sustain.stream;

  @override
  ValueListenable<Set<int>> get held => _held;

  void _onEvent(MidiDataReceivedEvent event) {
    final at = _nowSeconds();
    DiagLog.log(
      'midi-in',
      '${event.message.runtimeType} ${event.message.data} '
          'dev=${event.device.name}(${event.device.id}) '
          'plugin_ts=${event.timestamp} app_t=${at.toStringAsFixed(4)}',
    );
    handleMessage(event.message, atSeconds: at);
  }

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
        _sustain.add(SustainChange(value: value, atSeconds: atSeconds));
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
    unawaited(_resubscribeSub?.cancel());
    unawaited(_sub?.cancel());
    unawaited(_notes.close());
    unawaited(_sustain.close());
    _held.dispose();
  }
}

// M03: toca a partitura no teclado MIDI do próprio usuário, com o mesmo
// agendador de K04 (ver docs/plano/M03-saida-midi.md).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';

import '../audio/sound_engine.dart';

/// Interface única para "quem manda bytes MIDI a um dispositivo" — injetável
/// para teste (`FakeMidiSender` em test/midi_out_sound_engine_test.dart), sem
/// depender de um canal de plataforma de verdade.
abstract class MidiSender {
  void send(Uint8List data, {String? deviceId});
}

/// Implementação sobre `flutter_midi_command` (D-MIDI).
class FlutterMidiSender implements MidiSender {
  FlutterMidiSender([MidiCommand? midi]) : _midi = midi ?? MidiCommand();

  final MidiCommand _midi;

  @override
  void send(Uint8List data, {String? deviceId}) =>
      _midi.sendData(data, deviceId: deviceId);
}

/// Quanto antes do `at` agendado uma mensagem já pode sair — o `Timer`
/// interno acorda a cada [MidiOutSoundEngine._dispatchInterval] e despacha
/// tudo que já esteja a menos disto do horário.
const _kSendLeadSeconds = 0.002;

/// `SoundEngine` (K03) sobre um teclado MIDI externo (M03): a partitura toca
/// no som do próprio piano digital do usuário, via `MidiSender`.
///
/// Não há relógio de dispositivo como o motor nativo — [nowSeconds] é um
/// `Stopwatch` monotônico do app. O plugin não aceita timestamp futuro
/// (exceto Web MIDI — W03), então [schedule] só guarda os eventos numa fila
/// ordenada; um `Timer` curto ([_dispatchInterval]) despacha cada mensagem
/// quando `now >= at - _kSendLeadSeconds`.
class MidiOutSoundEngine implements SoundEngine {
  MidiOutSoundEngine({
    required MidiSender sender,
    required String deviceId,
    double Function()? nowSeconds,
    this.useScoreInstruments = false,
    this.forceChannel1 = false,
    Duration dispatchInterval = const Duration(milliseconds: 5),
    bool autoTick = true,
  }) : _sender = sender, // ignore: prefer_initializing_formals
       _deviceId = deviceId, // ignore: prefer_initializing_formals
       _dispatchInterval = dispatchInterval, // ignore: prefer_initializing_formals
       _autoTick = autoTick, // ignore: prefer_initializing_formals
       _nowSeconds = nowSeconds ?? _stopwatchClock();

  static double Function() _stopwatchClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds / 1e6;
  }

  final MidiSender _sender;
  final String _deviceId;
  final double Function() _nowSeconds;
  final Duration _dispatchInterval;
  final bool _autoTick;

  /// Manda o Program Change de cada canal da partitura (`NoteInfo.program`
  /// via [ScoreAudioScheduler]) — desligado por padrão: o usuário quer o som
  /// de piano do próprio teclado, não o instrumento da partitura.
  bool useScoreInstruments;

  /// Força todo evento a sair no canal 1 (nibble 0), ignorando o canal da
  /// partitura — o piano digital toca em qualquer canal no modo padrão, isto
  /// é só para quando o usuário pede explicitamente.
  bool forceChannel1;

  final List<ScheduledMidi> _queue = [];

  /// Teclas que este motor ligou e ainda não desligou (`channel << 8 |
  /// pitch`, já com [forceChannel1] aplicado) — [allNotesOff] manda note-off
  /// explícito para cada uma, porque alguns pianos ignoram CC123.
  final Set<int> _held = {};

  Timer? _timer;

  @override
  double get nowSeconds => _nowSeconds();

  /// Sem buffer nativo entre "agora" e o que ainda dá para agendar — a fila
  /// interna aceita qualquer `at >= nowSeconds`.
  @override
  double get earliestScheduleSeconds => nowSeconds;

  /// Fixo por ora; ajustável pela calibração de latência de T04.
  @override
  double get outputLatencySeconds => 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}

  @override
  void send(List<int> midi) {
    final rawStatus = midi[0];
    final kind = rawStatus & 0xF0;
    if (!useScoreInstruments && kind == 0xC0) return;
    final status = _applyChannelForce(rawStatus);
    _sendRaw(status, midi[1], midi[2]);
    if (kind == 0x90 || kind == 0x80) {
      _trackHeld(status, midi[1], isOn: kind == 0x90 && midi[2] > 0);
    }
  }

  @override
  void schedule(List<ScheduledMidi> events) {
    for (final e in events) {
      if (!useScoreInstruments && e.status & 0xF0 == 0xC0) continue;
      _queue.add(e);
    }
    _queue.sort((a, b) => a.at.compareTo(b.at));
    _armTimer();
    pump();
  }

  @override
  void clearScheduled() {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
  }

  @override
  void allNotesOff() {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    for (final key in _held.toList()) {
      _sendRaw(0x80 | (key >> 8), key & 0xFF, 0);
    }
    _held.clear();
    for (var channel = 0; channel < 16; channel++) {
      _sendRaw(0xB0 | channel, 123, 0); // all notes off
      _sendRaw(0xB0 | channel, 120, 0); // all sound off
      _sendRaw(0xB0 | channel, 64, 0); // sustain off
    }
  }

  @override
  Future<void> dispose() async {
    allNotesOff();
  }

  void _armTimer() {
    if (_autoTick) {
      _timer ??= Timer.periodic(_dispatchInterval, (_) => pump());
    }
  }

  /// Despacha tudo cujo `at` já chegou. O `Timer` interno chama isto
  /// sozinho; os testes chamam direto com relógio simulado (`autoTick:
  /// false`), no mesmo estilo de `ScoreAudioScheduler.pump`.
  void pump() {
    final now = nowSeconds;
    while (_queue.isNotEmpty && now >= _queue.first.at - _kSendLeadSeconds) {
      _dispatch(_queue.removeAt(0));
    }
    if (_queue.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _dispatch(ScheduledMidi event) {
    final kind = event.status & 0xF0;
    final status = _applyChannelForce(event.status);
    _sendRaw(status, event.d1, event.d2);
    if (kind == 0x90 || kind == 0x80) {
      _trackHeld(status, event.d1, isOn: kind == 0x90 && event.d2 > 0);
    }
  }

  int _applyChannelForce(int status) =>
      forceChannel1 ? (status & 0xF0) : status;

  void _trackHeld(int status, int pitch, {required bool isOn}) {
    final key = ((status & 0x0F) << 8) | pitch;
    if (isOn) {
      _held.add(key);
    } else {
      _held.remove(key);
    }
  }

  void _sendRaw(int status, int d1, int d2) {
    _sender.send(Uint8List.fromList([status, d1, d2]), deviceId: _deviceId);
  }
}

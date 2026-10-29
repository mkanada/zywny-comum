// Uma rodada do medidor de latência do som do teclado. O app abre o
// microfone, manda notas MIDI ao teclado e mede, em cada uma, o tempo entre o
// envio e a batida no microfone (`MicTimeline`).
//
// O microfone soma um atraso fixo à medida (o do hardware de captura, de 5 a
// 40 ms conforme o aparelho). Para tirá-lo, antes das notas o app toca alguns
// cliques no próprio alto-falante pelo motor de som, cujo instante de saída
// ele conhece (`SoundEngine.nowSeconds` já desconta a latência de saída): o
// que esses cliques medem a mais é o atraso do microfone. Sem motor, ou se o
// som não saiu pelo alto-falante (fone Bluetooth: o atraso medido passa de
// [kMeterMaxMicDelayMs]), vale a medida crua, avisada como tal.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_diag/diag_log.dart';
import 'package:zywny_midi/midi_out_sound_engine.dart' show MidiSender;

import 'latency_meter.dart';
import 'mic_capture.dart';

/// Notas mandadas ao teclado em cada rodada.
const int kMeterKeyboardPings = 8;

/// Cliques do alto-falante para medir o atraso do microfone.
const int kMeterReferencePings = 5;

/// Menos batidas que isto (do teclado) e não há medida.
const int kMeterMinHeard = 3;

/// Atraso de microfone acima disto não é microfone: é o som do app que não
/// saiu pelo alto-falante (fone Bluetooth, por exemplo).
const double kMeterMaxMicDelayMs = 100;

/// A nota do teste: dó5, forte, para a batida aparecer no microfone.
const int kMeterPitch = 72;
const int kMeterVelocity = 112;

/// A nota do alto-falante: bloco de madeira agudo (percussão, canal 10).
const int _kClickPitch = 76;

enum MeterPhase { idle, starting, reference, keyboard, analyzing, done, failed }

/// Por que não saiu medida.
enum MeterFailure {
  /// O aluno não deu a permissão do microfone.
  micDenied,

  /// O microfone não abriu.
  micUnavailable,

  /// O microfone não ouviu o teclado em número suficiente de notas.
  heardNothing,

  /// O aluno cancelou.
  cancelled,
}

/// O que a tela mostra durante a rodada.
@immutable
class MeterProgress {
  const MeterProgress(this.phase, {this.done = 0, this.total = 0});

  final MeterPhase phase;
  final int done;
  final int total;
}

/// Como foi a referência do alto-falante.
enum MeterReference {
  /// Não houve (sem motor de som, ou ele não abriu).
  skipped,

  /// O microfone não ouviu os cliques, ou o atraso não é de microfone.
  unreliable,

  /// O atraso do microfone foi medido e descontado.
  used,
}

/// O que saiu da rodada.
class LatencyMeterResult {
  const LatencyMeterResult.failed(this.failure, {this.heardSpeaker = false})
    : keyboard = null,
      reference = null,
      micDelayMs = null,
      referenceStatus = MeterReference.skipped,
      pingsMs = const [];

  const LatencyMeterResult({
    required this.keyboard,
    required this.reference,
    required this.micDelayMs,
    required this.referenceStatus,
    required this.pingsMs,
  }) : failure = null,
       heardSpeaker = false;

  final MeterFailure? failure;

  /// Só nas falhas: o microfone ouviu o alto-falante do celular (então o
  /// problema é o teclado, não o microfone).
  final bool heardSpeaker;

  /// A medida crua do teclado (envio → batida no microfone).
  final LatencyStats? keyboard;

  /// A medida crua do alto-falante.
  final LatencyStats? reference;

  /// O atraso do microfone que saiu da referência; `null` sem ela.
  final double? micDelayMs;
  final MeterReference referenceStatus;

  /// Cada nota do teclado, em ms crus; `null` quando não se ouviu.
  final List<double?> pingsMs;

  /// A latência do som do teclado, em ms: a medida menos o atraso do
  /// microfone, quando ele foi medido.
  double? get keyboardMs {
    final k = keyboard;
    if (k == null) return null;
    final mic = micDelayMs;
    final ms = mic == null ? k.medianMs : k.medianMs - mic;
    return ms < 0 ? 0 : ms;
  }

  /// O descontado do microfone foi medido (senão a medida inclui o atraso
  /// dele).
  bool get corrected => micDelayMs != null;
}

/// Uma rodada: [run] abre o microfone, toca e mede.
class LatencyMeterRunner {
  LatencyMeterRunner({
    required this.mic,
    required this.sender,
    required this.deviceId,
    this.openReference,
    double Function()? clock,
    Future<void> Function(Duration)? wait,
  }) : _clock = clock ?? _stopwatchClock(),
       _wait = wait ?? Future<void>.delayed;

  static double Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds / 1e6;
  }

  final MicCapture mic;
  final MidiSender sender;
  final String deviceId;

  /// Abre o motor de som do app para os cliques de referência; `null` (ou um
  /// motor que não abre) pula a referência.
  final Future<SoundEngine?> Function()? openReference;

  final double Function() _clock;
  final Future<void> Function(Duration) _wait;

  final ValueNotifier<MeterProgress> progress = ValueNotifier(
    const MeterProgress(MeterPhase.idle),
  );

  /// O volume que o microfone ouve agora (0..1), para a tela.
  final ValueNotifier<double> level = ValueNotifier(0);

  bool _cancelled = false;

  /// Para a rodada no próximo passo; [run] devolve o que tiver.
  void cancel() => _cancelled = true;

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    progress.dispose();
    level.dispose();
  }

  void _set(MeterPhase phase, [int done = 0, int total = 0]) {
    if (_disposed) return;
    progress.value = MeterProgress(phase, done: done, total: total);
  }

  Future<void> _pause(double seconds) async {
    if (_cancelled) throw const _Cancelled();
    await _wait(Duration(milliseconds: (seconds * 1000).round()));
    if (_cancelled) throw const _Cancelled();
  }

  Future<LatencyMeterResult> run() async {
    _set(MeterPhase.starting);
    final timeline = MicTimeline(sampleRate: mic.sampleRate);
    final sub = mic.chunks.listen((pcm) {
      timeline.add(pcm, _clock());
      if (!_disposed) level.value = timeline.level();
    });
    try {
      final failure = await mic.start();
      if (failure != null) {
        return LatencyMeterResult.failed(
          failure == MicFailure.denied
              ? MeterFailure.micDenied
              : MeterFailure.micUnavailable,
        );
      }
      final clicks = await _playReference();
      final sent = await _playKeyboard();
      _set(MeterPhase.analyzing);
      await _pause(0.8);
      return _analyze(timeline, clicks, sent);
    } on _Cancelled {
      return const LatencyMeterResult.failed(MeterFailure.cancelled);
    } finally {
      await sub.cancel();
      await mic.stop();
      sender.send(
        Uint8List.fromList([0x80, kMeterPitch, 0]),
        deviceId: deviceId,
      );
      _set(MeterPhase.done);
    }
  }

  /// Os cliques do alto-falante: devolve o instante em que cada um deve soar,
  /// no relógio do app. Vazio sem referência.
  Future<List<double>> _playReference() async {
    final open = openReference;
    if (open == null) {
      await _pause(0.6);
      return const [];
    }
    SoundEngine? engine;
    try {
      engine = await open();
    } on Object catch (e) {
      DiagLog.log('medidor', 'motor de referência não abriu: $e');
    }
    if (engine == null) {
      await _pause(0.6);
      return const [];
    }
    try {
      // O ruído de fundo antes do primeiro clique.
      await _pause(0.6);
      _set(MeterPhase.reference, 0, kMeterReferencePings);
      final delta = _engineDelta(engine);
      final first = engine.earliestScheduleSeconds + 0.4;
      final heard = <double>[];
      final events = <ScheduledMidi>[];
      for (var i = 0; i < kMeterReferencePings; i++) {
        final at = first + i * 0.9;
        heard.add(at + delta);
        events
          ..add(ScheduledMidi(at, 0x99, _kClickPitch, 127))
          ..add(ScheduledMidi(at + 0.1, 0x89, _kClickPitch, 0));
      }
      engine.schedule(events);
      for (var i = 0; i < kMeterReferencePings; i++) {
        _set(MeterPhase.reference, i, kMeterReferencePings);
        await _pause(i == 0 ? 0.4 + 0.9 : 0.9);
      }
      return heard;
    } finally {
      engine.allNotesOff();
      await engine.dispose();
    }
  }

  /// A diferença entre o relógio do app e o do motor, pela mediana de
  /// algumas leituras.
  double _engineDelta(SoundEngine engine) {
    final deltas = [for (var i = 0; i < 5; i++) _clock() - engine.nowSeconds]
      ..sort();
    return deltas[2];
  }

  /// As notas do teclado: devolve o instante de envio de cada uma.
  Future<List<double>> _playKeyboard() async {
    final sent = <double>[];
    for (var i = 0; i < kMeterKeyboardPings; i++) {
      _set(MeterPhase.keyboard, i, kMeterKeyboardPings);
      sent.add(_clock());
      sender.send(
        Uint8List.fromList([0x90, kMeterPitch, kMeterVelocity]),
        deviceId: deviceId,
      );
      await _pause(0.15);
      sender.send(
        Uint8List.fromList([0x80, kMeterPitch, 0]),
        deviceId: deviceId,
      );
      // Intervalo irregular, para não casar com um zumbido periódico.
      await _pause(1.15 + (i % 3) * 0.1);
    }
    return sent;
  }

  LatencyMeterResult _analyze(
    MicTimeline timeline,
    List<double> clicks,
    List<double> sent,
  ) {
    final clickMs = _onsetsMs(timeline, clicks);
    final reference = LatencyStats.of([
      for (final ms in clickMs) ?ms,
    ], total: clicks.length);
    final pingMs = _onsetsMs(timeline, sent);
    final keyboard = LatencyStats.of([
      for (final ms in pingMs) ?ms,
    ], total: sent.length);
    DiagLog.log('medidor', 'teclado=$pingMs referência=$clickMs');
    final heardSpeaker = reference != null && reference.used >= kMeterMinHeard;
    if (keyboard == null || keyboard.used < kMeterMinHeard) {
      return LatencyMeterResult.failed(
        MeterFailure.heardNothing,
        heardSpeaker: heardSpeaker,
      );
    }
    double? micDelay;
    var status = MeterReference.skipped;
    if (clicks.isNotEmpty) {
      final ok =
          heardSpeaker &&
          reference.medianMs >= 0 &&
          reference.medianMs <= kMeterMaxMicDelayMs &&
          reference.stdMs <= 15;
      status = ok ? MeterReference.used : MeterReference.unreliable;
      if (ok) micDelay = reference.medianMs;
    }
    return LatencyMeterResult(
      keyboard: keyboard,
      reference: reference,
      micDelayMs: micDelay,
      referenceStatus: status,
      pingsMs: pingMs,
    );
  }

  /// Cada instante de [sent] em ms até a batida; `null` onde não houve.
  List<double?> _onsetsMs(MicTimeline timeline, List<double> sent) => [
    for (final at in sent)
      switch (timeline.onsetAfter(at).seconds) {
        final onset? => (onset - at) * 1000,
        null => null,
      },
  ];
}

class _Cancelled implements Exception {
  const _Cancelled();
}

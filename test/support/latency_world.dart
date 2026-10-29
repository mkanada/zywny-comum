// O mundo simulado do medidor de latência: relógio virtual, teclado e
// alto-falante com latência conhecida, microfone com atraso fixo e jitter.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_comum/practice/latency_meter_runner.dart';
import 'package:zywny_comum/practice/mic_capture.dart';
import 'package:zywny_midi/midi_out_sound_engine.dart' show MidiSender;

const int _rate = 44100;

/// Um som de [freq] Hz que nasce em [start] e some em e^-t/[decay], na hora
/// física [t] (s).
class LatencyBurst {
  LatencyBurst(this.start, {this.decay = 0.25, this.freq = 523});

  final double start;
  final double decay;
  final double freq;

  double at(double t) {
    if (t < start) return 0;
    final dt = t - start;
    return 0.5 * math.exp(-dt / decay) * math.sin(2 * math.pi * freq * dt);
  }
}

/// O mundo da rodada: o relógio virtual, o que o microfone ouve e o que o
/// teclado e o alto-falante tocam.
class LatencyWorld implements MidiSender, MicCapture {
  LatencyWorld({
    this.keyboardMs = 45,
    this.micDelayMs = 20,
    this.speakerMs = 0,
    this.jitterMs = 6,
    this.keyboardLoud = true,
    this.noise = 0.0008,
  });

  /// Latência real do teclado (envio → som no ar).
  final double keyboardMs;

  /// Atraso do hardware do microfone (som no ar → pedaço entregue).
  final double micDelayMs;

  /// Quanto o alto-falante atrasa além do que o motor informa (Bluetooth).
  final double speakerMs;

  /// Atraso variável a mais na entrega de cada pedaço.
  final double jitterMs;
  final bool keyboardLoud;
  final double noise;

  double now = 100;
  final _rng = math.Random(7);
  final List<LatencyBurst> bursts = [];
  double _generatedUntil = 100;
  final StreamController<Int16List> _chunks = StreamController.broadcast(
    sync: true,
  );

  /// A diferença entre o relógio do motor e o do app.
  final double engineOffset = 37.5;

  @override
  int get sampleRate => _rate;

  @override
  Stream<Int16List> get chunks => _chunks.stream;

  @override
  Future<MicFailure?> start() async => null;

  @override
  Future<void> stop() async {}

  @override
  void send(Uint8List data, {String? deviceId}) {
    if (data[0] == 0x90 && keyboardLoud) {
      bursts.add(LatencyBurst(now + keyboardMs / 1000));
    }
  }

  Future<void> wait(Duration d) async {
    final end = now + d.inMicroseconds / 1e6;
    while (now < end) {
      final step = math.min(0.01, end - now);
      now += step;
      _deliver(now);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Entrega o que o microfone captou até a hora física `now - micDelay`; o
  /// jitter da entrega atrasa o relógio de chegada do pedaço seguinte.
  void _deliver(double arrival) {
    final until = arrival - micDelayMs / 1000;
    final n = ((until - _generatedUntil) * _rate).round();
    if (n <= 0) return;
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = _generatedUntil + i / _rate;
      var v = (_rng.nextDouble() * 2 - 1) * noise;
      for (final b in bursts) {
        v += b.at(t);
      }
      pcm[i] = (v * 32767).round().clamp(-32768, 32767);
    }
    _generatedUntil += n / _rate;
    // Chegada com jitter: só atrasa.
    final late = _rng.nextDouble() * jitterMs / 1000;
    final saved = now;
    now += late;
    _chunks.add(pcm);
    now = saved;
  }
}

/// Alto-falante do celular: o motor de som da referência.
class LatencyWorldSpeaker implements SoundEngine {
  LatencyWorldSpeaker(this.world);

  final LatencyWorld world;
  bool disposed = false;

  @override
  double get nowSeconds => world.now + world.engineOffset;

  @override
  double get earliestScheduleSeconds => nowSeconds;

  @override
  double get outputLatencySeconds => 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}

  @override
  void send(List<int> midi) {}

  @override
  void schedule(List<ScheduledMidi> events) {
    for (final e in events) {
      if (e.status == 0x99) {
        world.bursts.add(
          LatencyBurst(
            e.at - world.engineOffset + world.speakerMs / 1000,
            decay: 0.05,
            freq: 1800,
          ),
        );
      }
    }
  }

  @override
  void clearScheduled() {}

  @override
  void allNotesOff() {}

  @override
  Future<void> dispose() async => disposed = true;
}

LatencyMeterRunner latencyRunner(
  LatencyWorld world, {
  LatencyWorldSpeaker? speaker,
}) => LatencyMeterRunner(
  mic: world,
  sender: world,
  deviceId: 'kb',
  openReference: speaker == null ? null : () async => speaker,
  clock: () => world.now,
  wait: world.wait,
);

// O medidor de latência do som do teclado: a detecção da batida no sinal do
// microfone e a rodada inteira, num mundo simulado (relógio virtual, teclado
// e alto-falante com latência conhecida, microfone com atraso fixo e jitter).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/latency_meter.dart';
import 'package:zywny_comum/practice/latency_meter_runner.dart';

import 'support/latency_world.dart';

void main() {
  group('MicTimeline', () {
    test('acha a batida no instante do sinal (±2 ms)', () {
      final timeline = MicTimeline(sampleRate: 44100);
      const chunk = 441; // 10 ms
      var t = 0.0;
      // Silêncio de 1 s, um tom que entra em 1,2345 s, entregue sem atraso.
      for (var i = 0; i < 200; i++) {
        final pcm = Int16List(chunk);
        for (var k = 0; k < chunk; k++) {
          final s = t + k / 44100;
          final v = s >= 1.2345 ? 0.4 * math.sin(2 * math.pi * 440 * s) : 0.0;
          pcm[k] = (v * 32767).round();
        }
        t += chunk / 44100;
        timeline.add(pcm, 50 + t);
      }
      final onset = timeline.onsetAfter(50 + 1.0);
      expect(onset.seconds, isNotNull);
      expect(onset.seconds! - (50 + 1.2345), closeTo(0, 0.002));
    });

    test('silêncio não é batida', () {
      final timeline = MicTimeline(sampleRate: 44100);
      for (var i = 0; i < 300; i++) {
        timeline.add(Int16List(441), 10 + (i + 1) * 0.01);
      }
      expect(timeline.onsetAfter(11).miss, MeterMiss.silent);
    });

    test('som que começou um instante antes do envio é "ocupado"', () {
      final timeline = MicTimeline(sampleRate: 44100);
      for (var i = 0; i < 300; i++) {
        final pcm = Int16List(441);
        for (var k = 0; k < 441; k++) {
          final s = (i * 441 + k) / 44100;
          // Silêncio até 1,45 s; a nota nasce e o envio é em 1,5 s.
          if (s >= 1.45) {
            pcm[k] = (0.3 * 32767 * math.sin(2 * math.pi * 523 * s)).round();
          }
        }
        timeline.add(pcm, 10 + (i + 1) * 0.01);
      }
      expect(timeline.onsetAfter(11.5).miss, MeterMiss.busy);
    });

    test('um estalo de um bloco só não conta', () {
      final timeline = MicTimeline(sampleRate: 44100);
      for (var i = 0; i < 300; i++) {
        final pcm = Int16List(441);
        if (i == 150) {
          for (var k = 0; k < 44; k++) {
            pcm[k] = 20000;
          }
        }
        timeline.add(pcm, 10 + (i + 1) * 0.01);
      }
      expect(timeline.onsetAfter(11).miss, MeterMiss.silent);
    });
  });

  group('LatencyStats', () {
    test('mediana sem a medida fora de tom', () {
      final stats = LatencyStats.of([40, 42, 41, 43, 200, 39], total: 8)!;
      expect(stats.medianMs, closeTo(41, 1));
      expect(stats.used, 5);
      expect(stats.total, 8);
      expect(stats.stdMs, lessThan(3));
    });

    test('sem medida, nada', () {
      expect(LatencyStats.of([], total: 8), isNull);
    });
  });

  group('LatencyMeterRunner', () {
    test(
      'mede o teclado e tira o atraso do microfone com o alto-falante',
      () async {
        final world = LatencyWorld();
        final runner = latencyRunner(
          world,
          speaker: LatencyWorldSpeaker(world),
        );
        final result = await runner.run();
        expect(result.failure, isNull);
        expect(result.referenceStatus, MeterReference.used);
        // O microfone soma ~20 ms à medida crua.
        expect(result.micDelayMs, closeTo(20, 8));
        expect(result.keyboard!.medianMs, closeTo(65, 8));
        expect(result.keyboardMs, closeTo(45, 6));
        expect(result.corrected, isTrue);
        expect(result.pingsMs, hasLength(kMeterKeyboardPings));
      },
    );

    test(
      'outro aparelho: microfone mais lento, teclado pior, sala barulhenta',
      () async {
        final world = LatencyWorld(
          keyboardMs: 80,
          micDelayMs: 35,
          jitterMs: 12,
          noise: 0.004,
        );
        final result = await latencyRunner(
          world,
          speaker: LatencyWorldSpeaker(world),
        ).run();
        expect(result.failure, isNull);
        expect(result.micDelayMs, closeTo(35, 10));
        expect(result.keyboardMs, closeTo(80, 10));
      },
    );

    test('sem motor de referência, vale a medida crua e avisa', () async {
      final world = LatencyWorld();
      final result = await latencyRunner(world).run();
      expect(result.referenceStatus, MeterReference.skipped);
      expect(result.corrected, isFalse);
      expect(result.keyboardMs, closeTo(65, 8));
    });

    test(
      'alto-falante atrasado (fone Bluetooth) não serve de referência',
      () async {
        final world = LatencyWorld(speakerMs: 180);
        final result = await latencyRunner(
          world,
          speaker: LatencyWorldSpeaker(world),
        ).run();
        expect(result.referenceStatus, MeterReference.unreliable);
        expect(result.micDelayMs, isNull);
        expect(result.keyboardMs, closeTo(65, 8));
      },
    );

    test('teclado mudo: não ouviu nada, mas ouviu o celular', () async {
      final world = LatencyWorld(keyboardLoud: false);
      final result = await latencyRunner(
        world,
        speaker: LatencyWorldSpeaker(world),
      ).run();
      expect(result.failure, MeterFailure.heardNothing);
      expect(result.heardSpeaker, isTrue);
    });

    test('fecha o motor de referência e o microfone', () async {
      final world = LatencyWorld();
      final speaker = LatencyWorldSpeaker(world);
      await latencyRunner(world, speaker: speaker).run();
      expect(speaker.disposed, isTrue);
    });
  });

  test('o veredito cresce com a latência', () {
    expect(latencyVerdict(8), startsWith('Excelente'));
    expect(latencyVerdict(22), startsWith('Boa'));
    expect(latencyVerdict(45), contains('perceber'));
    expect(latencyVerdict(120), startsWith('Alta'));
  });
}

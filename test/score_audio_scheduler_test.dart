// K04: `ScoreAudioScheduler` com um `FakeSoundEngine` que só registra o que
// foi agendado — sem motor nativo, sem dispositivo de áudio, tempo simulado
// avançando `engine.now` e chamando `pump()` direto (`autoTick: false`), sem
// depender de `Timer.periodic` de verdade.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/audio/latency_calibration.dart';
import 'package:zywny/audio/metronome.dart';
import 'package:zywny/audio/score_audio_scheduler.dart';
import 'package:zywny/audio/sound_engine.dart';
import 'package:zywny/music/performance_track.dart';

class FakeSoundEngine implements SoundEngine {
  FakeSoundEngine({this.latency = 0.02});

  double now = 0;
  final double latency;

  /// Tudo que passou por [schedule], na ordem, nunca limpo — o "log" que os
  /// testes inspecionam (diferente da agenda do motor de verdade, que
  /// [allNotesOff] esvazia).
  final List<ScheduledMidi> scheduled = [];

  /// `earliestScheduleSeconds` no instante de cada `schedule()`, um valor
  /// por evento em [scheduled] (mesmo índice) — para conferir que nada foi
  /// agendado antes do que era possível naquele momento.
  final List<double> scheduledEarliest = [];

  /// `scheduled.length` no instante de cada [allNotesOff] — separa o log em
  /// "sessões" (play/seek/speed sempre silenciam antes de reagendar).
  final List<int> resetIndices = [];

  int allNotesOffCalls = 0;

  @override
  double get nowSeconds => now;

  @override
  double get earliestScheduleSeconds => now + latency;

  @override
  double get outputLatencySeconds => latency;

  @override
  Future<void> start() async {}

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}

  @override
  void send(List<int> midi) {}

  @override
  void schedule(List<ScheduledMidi> events) {
    final earliest = earliestScheduleSeconds;
    scheduled.addAll(events);
    scheduledEarliest.addAll(List.filled(events.length, earliest));
  }

  @override
  void clearScheduled() {}

  @override
  void allNotesOff() {
    allNotesOffCalls++;
    resetIndices.add(scheduled.length);
  }

  @override
  Future<void> dispose() async {}

  /// [scheduled], repartido nos pontos em que [allNotesOff] foi chamado.
  List<List<ScheduledMidi>> get sessions {
    final bounds = [0, ...resetIndices, scheduled.length]..sort();
    final result = <List<ScheduledMidi>>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      if (bounds[i + 1] > bounds[i]) {
        result.add(scheduled.sublist(bounds[i], bounds[i + 1]));
      }
    }
    return result;
  }
}

/// Quantos pares de eventos, mesmo canal e pitch, têm janelas
/// `[onMs, offMs)` que já se sobrepõem na própria peça (ornamento cuja
/// resolução cai antes do fim da nota anterior, por exemplo) — o agendador
/// não tem como evitar um 2º note-on antes do note-off do 1º nesses casos.
int _countSourceOverlaps(PerformanceTrack track) {
  final byKey = <int, List<SoundEvent>>{};
  for (final e in track.events) {
    byKey.putIfAbsent((e.channel << 8) | e.pitch, () => []).add(e);
  }
  var overlaps = 0;
  for (final events in byKey.values) {
    events.sort((a, b) => a.onMs.compareTo(b.onMs));
    for (var i = 0; i < events.length - 1; i++) {
      if (events[i + 1].onMs < events[i].offMs) overlaps++;
    }
  }
  return overlaps;
}

PerformanceTrack _loadTrack(String fixture) {
  final bytes = File('test/fixtures/$fixture').readAsBytesSync();
  final doc = VsbDocument.fromBytes(Uint8List.fromList(bytes));
  return PerformanceTrack.fromDocument(doc);
}

/// Simula o `Timer.periodic` chamando [ScoreAudioScheduler.pump] a cada
/// 25 ms de tempo do motor, até a posição musical alcançar [targetMs].
void _advanceUntil(
  FakeSoundEngine engine,
  ScoreAudioScheduler scheduler,
  double targetMs,
) {
  var guard = 0;
  while (scheduler.positionMs < targetMs) {
    engine.now += 0.025;
    scheduler.pump();
    guard++;
    // Tolerância folgada: a Gymnopédie/Maple Leaf Rag não passam de uns
    // poucos minutos, mesmo a speed 0.5 isso é bem menos de 100k passos.
    if (guard > 200000) {
      throw StateError('_advanceUntil não convergiu para $targetMs ms');
    }
  }
}

void main() {
  group('ScoreAudioScheduler', () {
    for (final speed in [1.0, 0.5]) {
      test('Gymnopédie inteira agenda 1 note-on + 1 note-off por evento, at '
          'correto (±1.5 ms) a speed $speed', () {
        final engine = FakeSoundEngine(latency: 0);
        final track = _loadTrack('erik-satie.vsb');
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );

        scheduler.play(0, speed: speed);
        _advanceUntil(engine, scheduler, track.durationMs);
        // Um pump extra para garantir que a última janela (que cobre até
        // durationMs) já tenha sido processada.
        engine.now += 1.0;
        scheduler.pump();

        final noteOns = engine.scheduled
            .where((m) => m.status & 0xF0 == 0x90)
            .toList();
        final noteOffs = engine.scheduled
            .where((m) => m.status & 0xF0 == 0x80)
            .toList();

        expect(noteOns.length, track.events.length);
        expect(noteOffs.length, track.events.length);

        // startingIn devolve os eventos na mesma ordem de track.events
        // (ordenado por onMs), e cada pump agenda o par onMs/offMs
        // junto — a ordem de agendamento reproduz a ordem original.
        for (var i = 0; i < track.events.length; i++) {
          final e = track.events[i];
          final on = noteOns[i];
          final off = noteOffs[i];

          expect(on.d1, e.pitch, reason: 'note-on $i: pitch');
          expect(on.status, 0x90 | e.channel, reason: 'note-on $i: canal');
          expect(
            on.at,
            closeTo(e.onMs / 1000 / speed, 0.0015),
            reason: 'note-on $i: at',
          );

          expect(off.d1, e.pitch, reason: 'note-off $i: pitch');
          expect(off.status, 0x80 | e.channel, reason: 'note-off $i: canal');
          expect(
            off.at,
            closeTo(e.offMs / 1000 / speed, 0.0015),
            reason: 'note-off $i: at',
          );
        }
      });
    }

    test(
      'pause no meio chama allNotesOff; nada é agendado depois até o play',
      () {
        final engine = FakeSoundEngine();
        final track = _loadTrack('maple-leaf-rag.vsb');
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );

        scheduler.play(0);
        _advanceUntil(engine, scheduler, track.durationMs / 2);

        final scheduledBeforePause = engine.scheduled.length;
        scheduler.pause();
        expect(engine.allNotesOffCalls, greaterThanOrEqualTo(1));
        final callsAfterPause = engine.allNotesOffCalls;

        // O Timer.periodic real teria sido cancelado, mas mesmo chamando
        // pump() manualmente (como se ele ainda estivesse rodando) nada
        // pode ser agendado enquanto pausado.
        for (var i = 0; i < 20; i++) {
          engine.now += 0.025;
          scheduler.pump();
        }
        expect(engine.scheduled.length, scheduledBeforePause);
        expect(engine.allNotesOffCalls, callsAfterPause);

        scheduler.play(scheduler.positionMs);
        scheduler.pump();
        expect(engine.scheduled.length, greaterThan(scheduledBeforePause));
      },
    );

    test('seek para trás e para frente não deixa note-on sem note-off dentro '
        'da mesma sessão (entre allNotesOff)', () {
      final engine = FakeSoundEngine();
      final track = _loadTrack('maple-leaf-rag.vsb');
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final mid = track.durationMs / 2;

      scheduler.play(0);
      _advanceUntil(engine, scheduler, mid);
      scheduler.seek(mid / 4); // para trás
      _advanceUntil(engine, scheduler, mid);
      scheduler.seek(mid * 1.5); // para frente, passando do que já tocou
      _advanceUntil(engine, scheduler, track.durationMs);

      // Duas notas do próprio corpus, mesma tecla, com janelas [onMs,
      // offMs) que já se sobrepõem no `PerformanceTrack` (ornamento cuja
      // resolução cai antes do fim da nota anterior) inevitavelmente
      // reagendam um 2º note-on antes do note-off do 1º — isso não é o
      // agendador duplicando nada, é a fonte. Cada sobreposição gera até
      // 2 "violações" (a colisão dos note-on e a dos note-off) e, como o
      // seek para trás cobre de novo um trecho já tocado, pode aparecer
      // em mais de uma das 3 sessões deste teste — o teto generoso
      // (sobreposições × 2 violações × 3 sessões) ainda fica bem longe
      // da contagem de um bug real (que afetaria muito mais teclas).
      final expectedOverlaps = _countSourceOverlaps(track) * 2 * 3;

      var violations = 0;
      for (final session in engine.sessions) {
        // O motor executa por `at` (um heap por quadro), não pela ordem
        // de chegada em schedule() — ordena por tempo antes de conferir
        // a alternância on/off de cada tecla (empate: mantém a ordem de
        // agendamento, via sort estável sobre o índice original).
        final byTime =
            List<MapEntry<int, ScheduledMidi>>.generate(
              session.length,
              (i) => MapEntry(i, session[i]),
            )..sort((a, b) {
              final byAt = a.value.at.compareTo(b.value.at);
              return byAt != 0 ? byAt : a.key.compareTo(b.key);
            });

        final open = <int, bool>{}; // (canal<<8 | pitch) -> soando?
        for (final entry in byTime) {
          final m = entry.value;
          final kind = m.status & 0xF0;
          if (kind != 0x90 && kind != 0x80) continue;
          final key = ((m.status & 0x0F) << 8) | m.d1;
          final isOn = kind == 0x90;
          final wasOn = open[key] ?? false;
          if (isOn == wasOn) violations++;
          open[key] = isOn;
        }
      }
      expect(
        violations,
        lessThanOrEqualTo(expectedOverlaps),
        reason:
            'note-on/note-off desalternados além do que a própria peça '
            'já sobrepõe ($expectedOverlaps) — indica religada indevida',
      );
    });

    test('nunca agenda antes de earliestScheduleSeconds', () {
      // Latência grande o bastante para forçar o clamp em algum evento
      // cedo da peça.
      final engine = FakeSoundEngine(latency: 0.5);
      final track = _loadTrack('r13-um-compasso.vsb');
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );

      scheduler.play(0);
      _advanceUntil(engine, scheduler, track.durationMs);
      engine.now += 1.0;
      scheduler.pump();

      expect(engine.scheduled, isNotEmpty);
      for (var i = 0; i < engine.scheduled.length; i++) {
        expect(
          engine.scheduled[i].at,
          greaterThanOrEqualTo(engine.scheduledEarliest[i] - 1e-9),
          reason: 'evento $i agendado antes do earliestScheduleSeconds',
        );
      }
    });

    group('freio do modo espera (T02)', () {
      test('posição estaciona no onMs armado e não passa dele', () {
        final engine = FakeSoundEngine();
        final track = _loadTrack('maple-leaf-rag.vsb');
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final brakeMs = track.durationMs / 3;

        scheduler.play(0);
        scheduler.setBrake(brakeMs);
        _advanceUntil(engine, scheduler, brakeMs);
        expect(scheduler.positionMs, brakeMs);

        // Tempo do dispositivo segue correndo por baixo: posição continua
        // parada exatamente no freio.
        for (var i = 0; i < 100; i++) {
          engine.now += 0.025;
          scheduler.pump();
        }
        expect(scheduler.positionMs, brakeMs);
      });

      test('com filtro de pauta, só agenda a pauta do app e nunca além do '
          'freio', () {
        final engine = FakeSoundEngine();
        final track = _loadTrack('maple-leaf-rag.vsb');
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final brakeMs = track.durationMs / 3;

        scheduler.setStaves({2});
        scheduler.play(0);
        scheduler.setBrake(brakeMs);
        _advanceUntil(engine, scheduler, brakeMs);
        for (var i = 0; i < 100; i++) {
          engine.now += 0.025;
          scheduler.pump();
        }

        final expected = track.events
            .where((e) => e.staff == 2 && e.onMs < brakeMs)
            .length;
        final noteOns = engine.scheduled
            .where((m) => m.status & 0xF0 == 0x90)
            .toList();
        expect(noteOns.length, expected);
        expect(noteOns, isNotEmpty);
        expect(
          noteOns.every(
            (m) => track.events.any(
              (e) =>
                  e.staff == 2 &&
                  e.pitch == m.d1 &&
                  e.channel == (m.status & 0x0F),
            ),
          ),
          isTrue,
          reason: 'nenhum note-on deveria vir da pauta 1 (do aluno)',
        );
      });

      test('avançar o freio (passo concluído) retoma o agendamento sem pular '
          'o que ficou parado', () {
        final engine = FakeSoundEngine();
        final track = _loadTrack('maple-leaf-rag.vsb');
        final scheduler = ScoreAudioScheduler(
          engine: engine,
          track: track,
          autoTick: false,
        );
        final brake1 = track.durationMs / 4;
        final brake2 = track.durationMs / 2;

        scheduler.play(0);
        scheduler.setBrake(brake1);
        _advanceUntil(engine, scheduler, brake1);
        // Fica "parado" um bom tempo — o relógio do dispositivo passa bem
        // além do que a posição musical mostra.
        for (var i = 0; i < 200; i++) {
          engine.now += 0.025;
          scheduler.pump();
        }

        scheduler.setBrake(brake2);
        _advanceUntil(engine, scheduler, brake2);
        expect(scheduler.positionMs, brake2);

        scheduler.setBrake(null);
        _advanceUntil(engine, scheduler, track.durationMs);
        engine.now += 1.0;
        scheduler.pump();

        final noteOns = engine.scheduled
            .where((m) => m.status & 0xF0 == 0x90)
            .length;
        expect(
          noteOns,
          track.events.length,
          reason: 'nenhum evento deveria ficar sem agendar',
        );
      });
    });
  });

  group('T04 loop A-B', () {
    test('2 compassos, 3 voltas: nenhuma nota presa e a posição volta a '
        'startMs a cada volta', () {
      final engine = FakeSoundEngine(latency: 0);
      final doc = VsbDocument.fromBytes(
        Uint8List.fromList(
          File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
        ),
      );
      final track = PerformanceTrack.fromDocument(doc);
      final measures = ScoreTimeline(doc).measures;
      final startMs = measures[1].startMs.toDouble();
      final endMs = measures[2].endMs.toDouble();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      )..setLoop(startMs, endMs);
      final laps = <int>[];
      scheduler.onLoop = laps.add;

      scheduler.play(startMs);
      final lapSeconds = (endMs - startMs) / 1000;
      var maxPositionAfterWrap = 0.0;
      var lastPos = startMs;
      var wraps = 0;
      while (engine.now < 3 * lapSeconds + 0.5) {
        engine.now += 0.025;
        scheduler.pump();
        final pos = scheduler.positionMs;
        expect(pos, inInclusiveRange(startMs - 1, endMs + 1));
        if (pos < lastPos - 1) {
          wraps++;
          expect(pos, closeTo(startMs, 60), reason: 'volta ao início');
          maxPositionAfterWrap = pos > maxPositionAfterWrap
              ? pos
              : maxPositionAfterWrap;
        }
        lastPos = pos;
      }
      expect(wraps, greaterThanOrEqualTo(3));
      expect(laps.length, greaterThanOrEqualTo(3));

      // Nenhuma nota soa através de uma fronteira de volta: simula o log.
      final log = [...engine.scheduled]..sort((a, b) => a.at.compareTo(b.at));
      final held = <int>{};
      var boundary = 1;
      for (final m in log) {
        while (boundary <= 3 && m.at > boundary * lapSeconds + 1e-6) {
          expect(held, isEmpty, reason: 'nota presa no fim da volta $boundary');
          boundary++;
        }
        final key = (m.status & 0x0F) << 8 | m.d1;
        switch (m.status & 0xF0) {
          case 0x90:
            held.add(key);
          case 0x80:
            held.remove(key);
        }
      }
      // Cada volta tocou a mesma quantidade de note-ons.
      final ons = log.where((m) => m.status & 0xF0 == 0x90).length;
      final perLap = track.startingIn(startMs, endMs).length;
      expect(ons, greaterThanOrEqualTo(3 * perLap));
    });
  });

  group('T04 metrônomo', () {
    test('Gymnopédie (3/4): batidas nos qstamp inteiros (±1 ms), 3 por '
        'compasso, tempo forte na 1ª', () {
      final doc = VsbDocument.fromBytes(
        Uint8List.fromList(
          File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
        ),
      );
      final timeline = ScoreTimeline(doc);
      final beats = metronomeBeats(timeline);
      final measures = timeline.measures;
      for (var m = 0; m < measures.length; m++) {
        final bar = beats.where((b) => b.measure == m).toList();
        expect(bar.length, 3, reason: 'compasso ${m + 1}');
        expect(bar.first.accent, isTrue);
        expect(bar.skip(1).any((b) => b.accent), isFalse);
      }
      // Cada entrada do timemap com qstamp inteiro relativo ao início do
      // compasso tem uma batida a ±1 ms.
      for (var m = 0; m < measures.length; m++) {
        final info = measures[m];
        final inBar = timeline.entries
            .where(
              (e) =>
                  e.qstamp != null &&
                  e.tstamp >= info.startMs &&
                  e.tstamp < info.endMs,
            )
            .toList();
        final q0 = inBar.first.qstamp!;
        for (final e in inBar) {
          final rel = e.qstamp! - q0;
          if (rel != rel.roundToDouble()) continue;
          expect(
            beats.any((b) => (b.ms - e.tstamp).abs() <= 1),
            isTrue,
            reason: 'compasso ${m + 1}: q=${e.qstamp} @${e.tstamp}',
          );
        }
      }
    });

    test(
      'metrônomo agenda cliques no canal 9 (76 no forte, 77 nos outros)',
      () {
        final engine = FakeSoundEngine(latency: 0);
        final doc = VsbDocument.fromBytes(
          Uint8List.fromList(
            File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
          ),
        );
        final track = PerformanceTrack.fromDocument(doc);
        final timeline = ScoreTimeline(doc);
        final scheduler =
            ScoreAudioScheduler(engine: engine, track: track, autoTick: false)
              ..beats = metronomeBeats(timeline)
              ..metronomeOn = true;
        scheduler.play(0);
        _advanceUntil(
          engine,
          scheduler,
          timeline.measures[3].startMs.toDouble(),
        );
        final clicks = engine.scheduled.where((m) => m.status == 0x99).toList();
        expect(clicks.length, greaterThanOrEqualTo(9));
        expect(
          [for (final c in clicks.take(6)) c.d1],
          [76, 77, 77, 76, 77, 77],
        );
      },
    );

    test('contagem: 1 compasso de cliques e posição parada em fromMs', () {
      final engine = FakeSoundEngine(latency: 0);
      final doc = VsbDocument.fromBytes(
        Uint8List.fromList(
          File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
        ),
      );
      final track = PerformanceTrack.fromDocument(doc);
      final timeline = ScoreTimeline(doc);
      final from = timeline.measures[2].startMs.toDouble();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      )..beats = metronomeBeats(timeline);
      scheduler.play(from, countIn: true);
      final barMs = timeline.measures[2].endMs - from;
      // Durante a contagem a posição não sai de `from`.
      for (var t = 0.0; t < barMs / 1000 * 0.9; t += 0.025) {
        engine.now += 0.025;
        scheduler.pump();
        expect(scheduler.positionMs, from);
      }
      final clicks = engine.scheduled.where((m) => m.status == 0x99).toList();
      expect(clicks.length, 3);
      expect(clicks.first.d1, 76);
      // Nenhuma nota antes de `from` (só depois da contagem).
      expect(
        engine.scheduled.where(
          (m) => m.status == 0x90 && m.at < barMs / 1000 - 0.01,
        ),
        isEmpty,
      );
    });
  });

  group('T04 calibração', () {
    test('mediana sem os 2 primeiros cliques', () {
      final clicks = [for (var i = 0; i < 8; i++) 1.0 + i * 0.6];
      // Os 2 primeiros com 300 ms de erro (ignorados); depois 40, 50, 60, 45,
      // 55, 42 ms.
      final offs = [0.3, 0.3, 0.040, 0.050, 0.060, 0.045, 0.055, 0.042];
      final presses = [for (var i = 0; i < 8; i++) clicks[i] + offs[i]];
      expect(calibrationLatencyMs(clicks, presses), closeTo(47.5, 1e-6));
    });

    test('sem teclas suficientes não mede', () {
      final clicks = [for (var i = 0; i < 8; i++) 1.0 + i * 0.6];
      expect(calibrationLatencyMs(clicks, [clicks[3] + 0.05]), isNull);
    });
  });
}

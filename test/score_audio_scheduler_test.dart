// K04: `ScoreAudioScheduler` com um `FakeSoundEngine` que só registra o que
// foi agendado — sem motor nativo, sem dispositivo de áudio, tempo simulado
// avançando `engine.now` e chamando `pump()` direto (`autoTick: false`), sem
// depender de `Timer.periodic` de verdade.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
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
      test(
        'Gymnopédie inteira agenda 1 note-on + 1 note-off por evento, at '
        'correto (±1.5 ms) a speed $speed',
        () {
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
            expect(
              off.status,
              0x80 | e.channel,
              reason: 'note-off $i: canal',
            );
            expect(
              off.at,
              closeTo(e.offMs / 1000 / speed, 0.0015),
              reason: 'note-off $i: at',
            );
          }
        },
      );
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

    test(
      'seek para trás e para frente não deixa note-on sem note-off dentro '
      'da mesma sessão (entre allNotesOff)',
      () {
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
          final byTime = List<MapEntry<int, ScheduledMidi>>.generate(
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
      },
    );

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
  });
}

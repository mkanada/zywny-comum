// T01, modo tempo real (docs/plano/T01-casador-de-notas.md). Critérios 3-5
// usam o corpus real (Gymnopédie); os demais usam eventos sintéticos para
// controlar exatamente onde cai cada fronteira de janela.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/practice/practice_session.dart';

SoundEvent _ev(
  String id,
  int pitch,
  double onMs, {
  int staff = 1,
  bool ornament = false,
}) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + 400,
  staff: staff,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: ornament,
);

PerformanceTrack _loadTrack(String fixture) {
  final bytes = File('test/fixtures/$fixture').readAsBytesSync();
  return PerformanceTrack.fromDocument(
    VsbDocument.fromBytes(Uint8List.fromList(bytes)),
  );
}

/// Ruído gaussiano (Box-Muller) com desvio padrão [sigma].
double _gaussianNoise(Random rng, double sigma) {
  final u1 = 1 - rng.nextDouble();
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2) * sigma;
}

void main() {
  group('RealtimeSession', () {
    test('Gymnopédie (pauta 1) "perfeita" com ruído gaussiano σ=20ms: '
        '≥99% correct, 0 wrong', () {
      final track = _loadTrack('erik-satie.vsb');
      final events =
          track.events.where((e) => e.staff == 1 && !e.ornament).toList()
            ..sort((a, b) => a.onMs.compareTo(b.onMs));
      expect(events, isNotEmpty);

      final session = RealtimeSession.forStaves(track, staves: {1}, speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      final rng = Random(7);
      for (final e in events) {
        session.noteOn(e.pitch, e.onMs + _gaussianNoise(rng, 20));
      }
      session.tick(track.durationMs + 1000);

      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.wrong),
        isEmpty,
      );
      final correct = verdicts
          .where((v) => v.kind == PracticeVerdictKind.correct)
          .length;
      expect(correct / events.length, greaterThanOrEqualTo(0.99));
    });

    test('pular um trecho inteiro sem tocar marca exatamente esses eventos '
        'como missed', () {
      final track = _loadTrack('erik-satie.vsb');
      final events =
          track.events.where((e) => e.staff == 1 && !e.ornament).toList()
            ..sort((a, b) => a.onMs.compareTo(b.onMs));
      expect(events.length, greaterThan(20));

      final session = RealtimeSession.forStaves(track, staves: {1}, speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      // "compasso" pulado: um miolo contíguo nunca tocado — as demais
      // notas tocadas certinhas ao redor.
      const skipStart = 5;
      const skipEnd = 9;
      final skippedIds = events
          .sublist(skipStart, skipEnd)
          .map((e) => e.id)
          .toSet();

      for (var i = 0; i < events.length; i++) {
        if (i >= skipStart && i < skipEnd) continue;
        session.noteOn(events[i].pitch, events[i].onMs);
      }
      session.tick(track.durationMs + 10000);

      final missedIds = verdicts
          .where((v) => v.kind == PracticeVerdictKind.missed)
          .map((v) => v.eventId)
          .toSet();
      expect(missedIds, skippedIds);
    });

    group(
      'a speed 0.5 (janelas de parede 75/150ms viram 37.5/75ms musicais)',
      () {
        test('exatamente na borda da janela ok (37.5ms) ainda é correct', () {
          final session = RealtimeSession([_ev('a', 60, 1000)], speed: 0.5);
          final verdicts = <NoteVerdict>[];
          session.verdicts.listen(verdicts.add);

          session.noteOn(60, 1000 + 37.5);
          expect(verdicts.single.kind, PracticeVerdictKind.correct);
        });

        test('logo além da janela ok vira late, não correct', () {
          final session = RealtimeSession([_ev('a', 60, 1000)], speed: 0.5);
          final verdicts = <NoteVerdict>[];
          session.verdicts.listen(verdicts.add);

          session.noteOn(60, 1000 + 38);
          expect(verdicts.single.kind, PracticeVerdictKind.late);
        });

        test('exatamente na borda da janela máxima (75ms) ainda casa', () {
          final session = RealtimeSession([_ev('a', 60, 1000)], speed: 0.5);
          final verdicts = <NoteVerdict>[];
          session.verdicts.listen(verdicts.add);

          session.noteOn(60, 1000 + 75);
          expect(verdicts.single.kind, PracticeVerdictKind.late);
        });

        test('logo além da janela máxima não casa mais: wrong', () {
          final session = RealtimeSession([_ev('a', 60, 1000)], speed: 0.5);
          final verdicts = <NoteVerdict>[];
          session.verdicts.listen(verdicts.add);

          session.noteOn(60, 1000 + 76);
          expect(verdicts.single.kind, PracticeVerdictKind.wrong);
          expect(verdicts.single.eventId, isNull);
        });
      },
    );

    test('sem candidata na janela: wrong, sem eventId', () {
      final session = RealtimeSession([_ev('a', 60, 1000)], speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(61, 1000);
      expect(verdicts.single.kind, PracticeVerdictKind.wrong);
      expect(verdicts.single.eventId, isNull);
    });

    test('missed só depois que a janela máxima passa de verdade', () {
      final session = RealtimeSession([_ev('a', 60, 1000)], speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.tick(1000 + 150); // ainda na borda, não perdeu
      expect(verdicts, isEmpty);

      session.tick(1000 + 150.0001);
      expect(verdicts.single.kind, PracticeVerdictKind.missed);
      expect(verdicts.single.eventId, 'a');
    });

    test(
      'ornamento pulado não vira missed, e nota real depois dele casa certo',
      () {
        final session = RealtimeSession([
          _ev('orn', 60, 1000, ornament: true),
          _ev('real', 60, 1200),
        ], speed: 1);
        final verdicts = <NoteVerdict>[];
        session.verdicts.listen(verdicts.add);

        // Passa da janela do ornamento (1000+150) mas não da da nota real
        // (1200+150) — só o ornamento deveria sumir, em silêncio.
        session.tick(1200);
        expect(verdicts, isEmpty);

        session.noteOn(60, 1200);
        expect(verdicts.single.kind, PracticeVerdictKind.correct);
        expect(verdicts.single.eventId, 'real');
      },
    );

    test('nota tocada perto de um ornamento não vira wrong (consumido em silêncio)', () {
      final session = RealtimeSession([
        _ev('orn', 60, 1000, ornament: true),
      ], speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(60, 1010);
      expect(verdicts, isEmpty);
    });

    test('resetTo descarta eventos antes do ponto e mantém os depois', () {
      final session = RealtimeSession([
        _ev('a', 60, 0),
        _ev('b', 62, 1000),
        _ev('c', 64, 2000),
      ], speed: 1);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.resetTo(900);
      session.tick(0); // 'a' já foi descartado antes do resetTo: sem missed
      expect(verdicts, isEmpty);

      session.noteOn(62, 1000);
      expect(verdicts.single.eventId, 'b');
    });
  });
}

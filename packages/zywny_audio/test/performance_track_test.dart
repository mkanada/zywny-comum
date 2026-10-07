// N03: `PerformanceTrack` é um adaptador puro de `VsbMidi` — os testes usam
// `.vsb` do corpus direto (sem passar pelo render/FFI), copiados de
// score_bridge/test/fixtures/ (ver docs/plano/N03-performance-track.md).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/performance_track.dart';

VsbDocument _load(String name) {
  final bytes = File('../../test/fixtures/$name').readAsBytesSync();
  return VsbDocument.fromBytes(Uint8List.fromList(bytes));
}

void main() {
  group('PerformanceTrack.fromDocument', () {
    for (final fixture in [
      'erik-satie.vsb',
      'maple-leaf-rag.vsb',
      'r13-um-compasso.vsb',
    ]) {
      test('$fixture: eventos são um mapeamento 1:1 de VsbMidi.notes', () {
        final doc = _load(fixture);
        final midi = doc.midi!;
        final track = PerformanceTrack.fromDocument(doc);

        expect(track.events.length, midi.notes.length);

        int compare((String, double, int) a, (String, double, int) b) {
          final byId = a.$1.compareTo(b.$1);
          if (byId != 0) return byId;
          final byOnMs = a.$2.compareTo(b.$2);
          return byOnMs != 0 ? byOnMs : a.$3.compareTo(b.$3);
        }

        final expected = midi.notes.map((n) => (n.id, n.onMs, n.pitch)).toList()
          ..sort(compare);
        final actual = track.events.map((e) => (e.id, e.onMs, e.pitch)).toList()
          ..sort(compare);
        expect(actual, expected);
      });
    }

    test(
      'Gymnopédie: ids -rend2 não se perdem nem se fundem com a passagem 1',
      () {
        final doc = _load('erik-satie.vsb');
        final track = PerformanceTrack.fromDocument(doc);

        final rend2 = track.events
            .where((e) => e.id.endsWith('-rend2'))
            .toList();
        expect(rend2, isNotEmpty);

        for (final e in rend2) {
          final baseId = e.id.substring(0, e.id.length - '-rend2'.length);
          final base = track.events.where((o) => o.id == baseId);
          expect(
            base,
            isNotEmpty,
            reason: 'esperava par da passagem 1 para $baseId',
          );
          final basePitchMatch = base.any((o) => o.pitch == e.pitch);
          expect(
            basePitchMatch,
            isTrue,
            reason: '${e.id} deveria repetir o pitch de $baseId',
          );
          expect(
            base.every((o) => o.onMs != e.onMs),
            isTrue,
            reason: '${e.id} deveria soar num tempo diferente da passagem 1',
          );
        }
      },
    );

    test('startingIn bate com um filtro linear em 1000 janelas aleatórias', () {
      final doc = _load('maple-leaf-rag.vsb');
      final track = PerformanceTrack.fromDocument(doc);
      final rng = Random(42);

      for (var i = 0; i < 1000; i++) {
        final a = rng.nextDouble() * track.durationMs;
        final b = rng.nextDouble() * track.durationMs;
        final fromMs = min(a, b);
        final toMs = max(a, b);

        final expected = track.events
            .where((e) => e.onMs >= fromMs && e.onMs < toMs)
            .map((e) => e.id)
            .toSet();
        final actual = track.startingIn(fromMs, toMs).map((e) => e.id).toSet();

        expect(actual, expected, reason: 'janela [$fromMs, $toMs)');
      }
    });

    test('startingIn filtra por pauta quando staves é informado', () {
      final doc = _load('maple-leaf-rag.vsb');
      final track = PerformanceTrack.fromDocument(doc);

      final actual = track
          .startingIn(0, track.durationMs, staves: {1})
          .toList();
      expect(actual, isNotEmpty);
      expect(actual.every((e) => e.staff == 1), isTrue);
    });

    test('chords agrupa notas conhecidas do corpus (Maple Leaf Rag)', () {
      final doc = _load('maple-leaf-rag.vsb');
      final track = PerformanceTrack.fromDocument(doc);

      final chords = track.chords(staves: {2});
      expect(chords, isNotEmpty);
      expect(chords.every((c) => c.staff == 2), isTrue);

      final atZero = chords.firstWhere((c) => c.onMs == 0);
      expect(atZero.notes.map((e) => e.pitch).toSet(), {39, 51});

      final at600 = chords.firstWhere((c) => c.onMs == 600);
      expect(at600.notes.map((e) => e.pitch).toSet(), {51, 56, 60});
    });

    test('peça sem midi.json vira uma track vazia, sem lançar exceção', () {
      final doc = _load('r13-sem-midi.vsb');
      expect(doc.midi, isNull);

      final track = PerformanceTrack.fromDocument(doc);
      expect(track.events, isEmpty);
      expect(track.pedal, isEmpty);
      expect(track.durationMs, 0);
      expect(track.staves, isEmpty);
    });
  });
}

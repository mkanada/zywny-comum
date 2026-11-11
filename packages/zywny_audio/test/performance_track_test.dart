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

  group('without', () {
    SoundEvent ev(String id, int pitch, double onMs) => SoundEvent(
      id: id,
      pitch: pitch,
      onMs: onMs,
      offMs: onMs + 400,
      staff: 1,
      channel: 0,
      program: 0,
      velocity: 80,
      ornament: false,
    );

    test('tira as notas dos ids e deixa as outras', () {
      final track = PerformanceTrack.fromEvents([
        ev('a', 60, 0),
        ev('b', 64, 500),
        ev('c', 67, 1000),
      ]);
      expect(
        [
          for (final e in track.without({'b'}).events) e.id,
        ],
        ['a', 'c'],
      );
      expect(track.without({}), same(track));
    });
  });

  group('withOrnaments: app (issue 22)', () {
    SoundEvent ev(
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

    final track = PerformanceTrack.fromEvents([
      ev('a', 60, 0),
      ev('b', 64, 500, staff: 2),
      ev('c', 67, 1000),
    ]);

    test(
      'um id em app sai com ornament e byApp; os outros ficam como estavam',
      () {
        final out = track.withOrnaments(app: {'a'});
        final a = out.events.firstWhere((e) => e.id == 'a');
        final c = out.events.firstWhere((e) => e.id == 'c');
        expect(a.ornament, isTrue);
        expect(a.byApp, isTrue);
        expect(c.ornament, isFalse);
        expect(c.byApp, isFalse);
      },
    );

    test('um id em app e em expand: todas as partes com ornament e byApp', () {
      final out = track.withOrnaments(
        app: {'a'},
        expand: {
          'a': const [OrnamentNote(62, 0, .5), OrnamentNote(60, .5, 1)],
        },
      );
      final parts = out.events.where((e) => e.id == 'a').toList();
      expect([for (final e in parts) e.pitch], [62, 60]);
      expect([for (final e in parts) e.ornament], [true, true]);
      expect([for (final e in parts) e.byApp], [true, true]);
    });

    test(
      'um id em app e em tremoloHeads: a cabeça não volta a ser cobrada',
      () {
        final trem = PerformanceTrack.fromEvents([
          ev('t', 72, 0, ornament: true),
          ev('t', 72, 50, ornament: true),
        ]);
        final out = trem.withOrnaments(tremoloHeads: true, app: {'t'});
        expect([for (final e in out.events) e.ornament], [true, true]);
        expect([for (final e in out.events) e.byApp], [true, true]);
      },
    );

    test('startingIn com staves vazio devolve só os eventos byApp', () {
      final out = track.withOrnaments(app: {'a'});
      final ids = out.startingIn(0, 2000, staves: const {}).map((e) => e.id);
      expect(ids.toList(), ['a']);
    });

    test(
      'startingIn com staves {1} devolve a pauta 1 e os byApp da pauta 2',
      () {
        final out = track.withOrnaments(app: {'b'});
        final ids = out.startingIn(0, 2000, staves: {1}).map((e) => e.id);
        // 'a' e 'c' são da pauta 1; 'b' é da pauta 2, mas byApp.
        expect(ids.toList(), ['a', 'b', 'c']);
      },
    );

    test('sem app, withOrnaments() continua devolvendo a própria trilha', () {
      expect(identical(track.withOrnaments(), track), isTrue);
    });
  });
}

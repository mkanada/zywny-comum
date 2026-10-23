// T10 do zywny-aprendizado: a janela adaptativa e o perdão da nota a mais
// que soa (`RealtimeSession.adaptiveWindow`, `forgiveSounding`), com eventos
// sintéticos. Desligadas, a sessão é a de sempre.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/practice/practice_session.dart';

SoundEvent _ev(
  String id,
  int pitch,
  double onMs, {
  double length = 100,
  int staff = 1,
  bool ornament = false,
}) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + length,
  staff: staff,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: ornament,
);

/// [count] semicolcheias no dó5 a ♩ = 120: uma a cada 125 ms.
List<SoundEvent> _repeated(int count) => [
  for (var i = 0; i < count; i++) _ev('r$i', 72, i * 125.0, length: 120),
];

/// Toca [presses] (altura, ms) em ordem, com um tick depois de cada uma e um
/// no fim, e devolve os vereditos.
List<NoteVerdict> _play(
  RealtimeSession session,
  List<(int, double)> presses, {
  double endMs = 10000,
}) {
  final verdicts = <NoteVerdict>[];
  session.verdicts.listen(verdicts.add);
  for (final (pitch, ms) in presses) {
    session.noteOn(pitch, ms);
    session.tick(ms);
  }
  session.tick(endMs);
  return verdicts;
}

int _count(List<NoteVerdict> v, PracticeVerdictKind kind) =>
    v.where((x) => x.kind == kind).length;

void main() {
  group('janela adaptativa', () {
    test('repetidas 70 ms atrasadas: sem ela, perde uma; com ela, nenhuma', () {
      final presses = [for (var i = 0; i < 16; i++) (72, i * 125.0 + 70)];
      final fixed = _play(RealtimeSession(_repeated(16), speed: 1), presses);
      expect(_count(fixed, PracticeVerdictKind.missed), 1);
      expect(_count(fixed, PracticeVerdictKind.wrong), 1);

      final adaptive = _play(
        RealtimeSession(_repeated(16), speed: 1, adaptiveWindow: true),
        presses,
      );
      expect(_count(adaptive, PracticeVerdictKind.missed), 0);
      expect(_count(adaptive, PracticeVerdictKind.wrong), 0);
      // Cada tecla casou com a sua nota, na ordem.
      expect(
        [for (final v in adaptive) v.eventId],
        [for (var i = 0; i < 16; i++) 'r$i'],
      );
    });

    test('a de certo encolhe com o intervalo', () {
      // 70 ms depois: dentro dos 75 de sempre, fora da metade de 125.
      final fixed = _play(RealtimeSession(_repeated(2), speed: 1), [(72, 70)]);
      expect(fixed.first.kind, PracticeVerdictKind.correct);
      final adaptive = _play(
        RealtimeSession(_repeated(2), speed: 1, adaptiveWindow: true),
        [(72, 70)],
      );
      expect(adaptive.first.kind, PracticeVerdictKind.late);
    });

    test('a nota pulada vira perdida no lugar dela, sem cascata', () {
      final presses = [
        for (var i = 0; i < 16; i++)
          if (i != 5) (72, i * 125.0),
      ];
      final v = _play(
        RealtimeSession(_repeated(16), speed: 1, adaptiveWindow: true),
        presses,
      );
      expect(_count(v, PracticeVerdictKind.missed), 1);
      expect(
        v.firstWhere((x) => x.kind == PracticeVerdictKind.missed).eventId,
        'r5',
      );
      expect(_count(v, PracticeVerdictKind.correct), 15);
    });

    test('antes da nota, a janela é a metade do intervalo', () {
      // Duas notas a 200 ms: a tecla 90 ms antes da segunda, com a primeira
      // já casada, é a segunda, adiantada; 110 ms antes já não é de nenhuma.
      final events = [_ev('a', 72, 0), _ev('b', 72, 200)];
      final v = _play(RealtimeSession(events, speed: 1, adaptiveWindow: true), [
        (72, 0),
        (72, 110),
      ]);
      expect([for (final x in v) x.eventId], ['a', 'b']);
      expect(v.last.kind, PracticeVerdictKind.early);
      final far = _play(
        RealtimeSession(events, speed: 1, adaptiveWindow: true),
        [(72, 0), (72, 90)],
      );
      expect(far[1].kind, PracticeVerdictKind.wrong);
    });

    test('notas afastadas: as janelas de sempre', () {
      final events = [_ev('a', 60, 0), _ev('b', 60, 1000)];
      final v = _play(RealtimeSession(events, speed: 1, adaptiveWindow: true), [
        (60, 140),
        (60, 1000 - 140),
      ]);
      expect(_count(v, PracticeVerdictKind.late), 1);
      expect(_count(v, PracticeVerdictKind.early), 1);
      expect(_count(v, PracticeVerdictKind.missed), 0);
    });

    test('outra pauta não encolhe a janela', () {
      final events = [_ev('a', 60, 0), _ev('b', 60, 100, staff: 2)];
      final session = RealtimeSession(events, speed: 1, adaptiveWindow: true);
      final v = _play(session, [(60, 140), (60, 150)]);
      // A mais antiga primeiro: a 'a' atrasada, depois a 'b'.
      expect([for (final x in v) x.eventId], ['a', 'b']);
    });
  });

  group('perdão da nota a mais que soa', () {
    // Um acorde de 5 notas segurado por 1 s.
    final chord = [
      for (final (i, p) in [60, 64, 67, 72, 76].indexed)
        _ev('k$i', p, 0, length: 1000),
    ];

    test('a nota do acorde tocada de novo não é errada; a de fora é', () {
      final presses = [for (final e in chord) (e.pitch, 0.0)];
      final strict = _play(RealtimeSession(chord, speed: 1), [
        ...presses,
        (76, 300),
      ]);
      expect(_count(strict, PracticeVerdictKind.wrong), 1);
      final forgiving = _play(
        RealtimeSession(chord, speed: 1, forgiveSounding: true),
        [...presses, (76, 300), (78, 300)],
      );
      expect(_count(forgiving, PracticeVerdictKind.wrong), 1);
      expect(
        forgiving.firstWhere((x) => x.kind == PracticeVerdictKind.wrong).pitch,
        78,
      );
    });

    test('a tocada tarde demais conta só como perdida', () {
      final events = [_ev('a', 60, 0, length: 500)];
      final v = _play(
        RealtimeSession(
          events,
          speed: 1,
          adaptiveWindow: true,
          forgiveSounding: true,
        ),
        [(60, 300)],
      );
      expect(_count(v, PracticeVerdictKind.missed), 1);
      expect(_count(v, PracticeVerdictKind.wrong), 0);
    });

    test('a nota de cima do trilo, além das escritas, não é errada', () {
      // O trilo de ré5 em fusas (100 ms), de cima: mi, ré, mi, ré.
      final trill = PerformanceTrack.fromEvents([_ev('t', 74, 0, length: 400)])
          .withOrnaments(
            expand: {
              't': const [
                OrnamentNote(76, 0, .25),
                OrnamentNote(74, .25, .5),
                OrnamentNote(76, .5, .75),
                OrnamentNote(74, .75, 1),
              ],
            },
          );
      final session = RealtimeSession(
        trill.events,
        speed: 1,
        adaptiveWindow: true,
        forgiveSounding: true,
      );
      // Um trilo mais rápido que o escrito: seis notas em vez de quatro.
      final v = _play(session, [
        for (var k = 0; k < 6; k++) (k.isEven ? 76 : 74, k * 66.0),
      ]);
      expect(_count(v, PracticeVerdictKind.wrong), 0);
      expect(_count(v, PracticeVerdictKind.missed), 0);
      // Só a nota principal é cobrada.
      expect(v.where((x) => x.eventId != null).length, 1);
    });
  });

  group('PerformanceTrack.withOrnaments', () {
    final track = PerformanceTrack.fromEvents([
      _ev('n', 74, 1000, length: 800),
      _ev('g', 76, 970, length: 30),
      _ev('m', 72, 2000, ornament: true),
      _ev('m', 72, 2025, ornament: true),
      _ev('m', 72, 2050, ornament: true),
    ]);

    test('o ornamento por extenso: só a nota principal é cobrada', () {
      final out = track.withOrnaments(
        expand: {
          'n': const [
            OrnamentNote(76, 0, .125),
            OrnamentNote(74, .125, .25),
            OrnamentNote(76, .25, .375),
            OrnamentNote(74, .375, 1),
          ],
        },
      );
      final notes = out.events.where((e) => e.id == 'n').toList();
      expect([for (final e in notes) e.pitch], [76, 74, 76, 74]);
      expect([for (final e in notes) e.onMs], [1000, 1100, 1200, 1300]);
      expect([for (final e in notes) e.ornament], [true, false, true, true]);
      expect(notes.last.offMs, 1800);
    });

    test('a apojatura breve vira ornamento', () {
      final out = track.withOrnaments(free: {'g'});
      expect(out.events.firstWhere((e) => e.id == 'g').ornament, isTrue);
      expect(out.events.firstWhere((e) => e.id == 'n').ornament, isFalse);
    });

    test('o trêmolo: a primeira nota é cobrada', () {
      final out = track.withOrnaments(tremoloHeads: true);
      final m = out.events.where((e) => e.id == 'm').toList();
      expect([for (final e in m) e.ornament], [false, true, true]);
    });

    test('sem nada, a mesma track', () {
      expect(identical(track.withOrnaments(), track), isTrue);
    });
  });
}

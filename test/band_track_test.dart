// T15 — a banda na trilha e no agendador: as pautas que o app toca (com e sem
// banda), a soma das notas da banda na trilha, e o interruptor, o volume, a
// introdução e os cliques da contagem no `ScoreAudioScheduler`.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/metronome.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_comum/practice/app_hand.dart';
import 'package:zywny_comum/practice/hand.dart';

import 'support/practice_fakes.dart';

SoundEvent _note(
  String id, {
  required int staff,
  required double onMs,
  int pitch = 60,
  int channel = 0,
  int program = 0,
  int velocity = 80,
}) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + 400,
  staff: staff,
  channel: channel,
  program: program,
  velocity: velocity,
  ornament: false,
);

/// Uma peça de duas notas do aluno (pauta 1) e uma banda de quatro pautas.
PerformanceTrack _score() => PerformanceTrack.fromEvents([
  _note('n1', staff: 1, onMs: 0),
  _note('n2', staff: 2, onMs: 1000),
]);

List<SoundEvent> _band() => [
  _note('band-d', staff: 3, onMs: 500, pitch: 36, channel: 9, velocity: 60),
  _note(
    'band-b',
    staff: 4,
    onMs: 0,
    pitch: 31,
    channel: 1,
    program: 33,
    velocity: 80,
  ),
];

void main() {
  group('as pautas que o app toca', () {
    test('com a banda: a outra mão e as pautas 3 a 6', () {
      expect(Hand.esquerda.appStaves, {1, 3, 4, 5, 6});
      expect(Hand.direita.appStaves, {2, 3, 4, 5, 6});
      expect(Hand.ambas.appStaves, {3, 4, 5, 6});
    });

    test('o que o aluno toca não muda', () {
      expect(Hand.esquerda.studentStaves, {2});
      expect(Hand.direita.studentStaves, {1});
      expect(Hand.ambas.studentStaves, {1, 2});
    });

    test('sem banda na trilha, "ambas" não toca nenhuma nota', () {
      expect(appHandNoteIds(_score(), Hand.ambas), isEmpty);
    });
  });

  group('PerformanceTrack.withBand', () {
    test('sem notas, é a própria trilha', () {
      final track = _score();
      expect(identical(track.withBand(const []), track), isTrue);
    });

    test('soma as notas da banda na ordem de onMs, sem mudar as pautas', () {
      final track = _score().withBand(_band());
      expect(
        [for (final e in track.events) e.id],
        ['band-b', 'n1', 'band-d', 'n2'],
      );
      expect(track.staves, {1, 2});
    });

    test('a banda não entra no que o aluno toca', () {
      final track = _score().withBand(_band());
      final played = [
        for (final e in track.startingIn(
          0,
          5000,
          staves: Hand.direita.studentStaves,
        ))
          e.id,
      ];
      expect(played, ['n1']);
    });

    test('a banda só aparece para quem toca com a pauta dela', () {
      final track = _score().withBand(_band());
      final app = appHandNoteIds(track, Hand.direita);
      expect(app, containsAll(['band-b', 'band-d']));
      expect(app, isNot(contains('n1')));
    });
  });

  group('o agendador', () {
    late FakeSoundEngine engine;

    setUp(() => engine = FakeSoundEngine());

    ScoreAudioScheduler scheduler(PerformanceTrack track) {
      final s = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      s.setStaves(Hand.direita.appStaves);
      return s;
    }

    List<ScheduledMidi> noteOns(int channel) => [
      for (final m in engine.scheduled)
        if (m.status == (0x90 | channel) && m.d2 > 0) m,
    ];

    test('a banda sai com o volume na velocity', () {
      final s = scheduler(_score().withBand(_band()))..bandVolume = 50;
      s.play(0);
      final bass = noteOns(1);
      expect(bass, hasLength(1));
      expect(bass.single.d2, 40);
    });

    test('com a banda desligada, nada dela soa', () {
      final s = scheduler(_score().withBand(_band()))..bandOn = false;
      s.play(0);
      expect(noteOns(1), isEmpty);
      expect(noteOns(9), isEmpty);
    });

    test('a mudança de volume vale na próxima nota agendada', () {
      final s = scheduler(_score().withBand(_band()));
      s.play(0);
      // A bateria (em 500 ms) ainda não foi agendada: sai com o volume novo.
      s.bandVolume = 10;
      engine.now = 0.4;
      s.pump();
      expect(noteOns(9).single.d2, 6);
    });

    test('a introdução soa na contagem, sem os cliques', () {
      final beats = [
        for (var i = 0; i < 4; i++) Beat(i * 500.0, accent: i == 0, measure: 0),
        for (var i = 0; i < 4; i++)
          Beat(2000 + i * 500.0, accent: i == 0, measure: 1),
      ];
      final s = scheduler(_score().withBand(_band()))
        ..beats = beats
        ..countInClicks = false
        ..leadIn = [
          _note('lead-d', staff: 3, onMs: -2000, pitch: 36, channel: 9),
        ];
      s.play(0, countIn: true);
      final drums = noteOns(9);
      expect(drums.where((m) => m.d1 == 36), hasLength(1));
      expect(
        drums.where(
          (m) => m.d1 == kMetronomeNote || m.d1 == kMetronomeAccentNote,
        ),
        isEmpty,
        reason: 'sem os cliques da contagem',
      );
    });

    test('com os cliques ligados, a contagem clica como sempre', () {
      final beats = [
        for (var i = 0; i < 4; i++) Beat(i * 500.0, accent: i == 0, measure: 0),
      ];
      final s = scheduler(_score())..beats = beats;
      s.play(0, countIn: true);
      expect(noteOns(kMetronomeChannel), isNotEmpty);
    });

    test('manda o programa dos canais da introdução', () {
      final s = scheduler(_score().withBand(_band()))
        ..leadIn = [
          _note('lead-d', staff: 3, onMs: -2000, pitch: 36, channel: 9),
        ];
      s.play(0);
      final programs = [
        for (final m in engine.scheduled)
          if ((m.status & 0xF0) == 0xC0) m.status & 0x0F,
      ];
      expect(programs, containsAll([0, 1, 9]));
    });
  });
}

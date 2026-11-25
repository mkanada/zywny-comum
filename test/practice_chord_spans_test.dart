// AC05a e AC05b do AC00 ("Tocar pela cifra"): o acorde da cifra no modo espera
// (AC05a) e no tempo real (AC05b). No modo espera, a `WaitModeSession` cobra o
// acorde de um passo como as notas (com as teclas presas, sem janela de tempo);
// no tempo real, a `RealtimeSession` dá ao acorde uma janela por ataque, com a
// tolerância das notas, e decide no fim dela (correct/early/late ou missed). A
// tecla que o acorde não aceita é errada, no compasso certo; a escada (LP25)
// repete o compasso com erro de acorde. Sem demandas, nada muda. Os acordes aqui
// são falsos (classes de altura): a grade da cifra e o juiz são testados no app
// (`test/chord_play`).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/metronome.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_comum/practice/chord_demand.dart';
import 'package:zywny_comum/practice/hand.dart';
import 'package:zywny_comum/practice/practice_controller.dart';
import 'package:zywny_comum/practice/practice_session.dart';

import 'support/practice_fakes.dart';

/// Um acorde de teste: as classes [classes] (qualquer inversão e oitava) no
/// ataque [onMs]. Cumpre quando todas as classes estão apertadas.
class _Chord implements ChordDemand {
  const _Chord(this.onMs, this.classes);

  @override
  final double onMs;
  final Set<int> classes;

  @override
  bool allows(int pitch) => classes.contains(pitch % 12);

  @override
  bool satisfied(Set<int> pressed) =>
      classes.every((c) => pressed.any((p) => p % 12 == c));
}

/// Um ataque que não se cobra (como o N.C.): já vale sem nenhuma tecla.
class _Free implements ChordDemand {
  const _Free(this.onMs);

  @override
  final double onMs;

  @override
  bool allows(int pitch) => true;

  @override
  bool satisfied(Set<int> pressed) => true;
}

/// Dó maior: as classes 0, 4 e 7.
const _cMajor = {0, 4, 7};

/// Dó maior numa altura, o que o aluno aperta no acorde (duas oitavas, dó 3,
/// mi 3 e sol 3, na mão esquerda).
const _cMajorKeys = [48, 52, 55];

SoundEvent _ev(String id, int pitch, double onMs) => SoundEvent(
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

/// Um passo só de acorde, sem nota da partitura, em [onMs].
PracticeStep _chordStep(int index, double onMs, ChordDemand chord) =>
    PracticeStep(
      index: index,
      onMs: onMs,
      notes: const [],
      remaining: const {},
      chord: chord,
    );

/// Um passo de melodia [pitch] com o acorde [chord] no mesmo ataque.
PracticeStep _mixedStep(int index, double onMs, int pitch, ChordDemand chord) =>
    PracticeStep(
      index: index,
      onMs: onMs,
      notes: [_ev('m$index', pitch, onMs)],
      remaining: {pitch},
      chord: chord,
    );

/// Os vereditos de [session], na ordem.
List<NoteVerdict> _listen(WaitModeSession session) {
  final verdicts = <NoteVerdict>[];
  session.verdicts.listen(verdicts.add);
  return verdicts;
}

/// As exigências de acorde do compasso 1 do `erik-satie`: dó maior em cada
/// ataque da mão do aluno.
List<ChordDemand> _measureOneChords(
  PerformanceTrack track,
  ScoreTimeline timeline,
) {
  final m = timeline.measures[1];
  final onsets = <double>{
    for (final e in track.events)
      if (Hand.direita.studentStaves.contains(e.staff) &&
          !e.ornament &&
          e.onMs >= m.startMs &&
          e.onMs < m.endMs)
        e.onMs,
  }.toList()..sort();
  return [for (final onMs in onsets) _Chord(onMs, _cMajor)];
}

VsbDocument _loadDoc() => VsbDocument.fromBytes(
  Uint8List.fromList(File('test/fixtures/erik-satie.vsb').readAsBytesSync()),
);

/// Uma rodada nos compassos 1 e 2 do `erik-satie` (o mesmo arranjo de
/// `practice_rewind_test.dart`), no modo espera ou no tempo real (AC05b), com as
/// exigências de acorde que [chordsOf] der.
class _Rig {
  _Rig({this.chordsOf, this.mode = PracticeMode.wait}) {
    final doc = _loadDoc();
    track = PerformanceTrack.fromDocument(doc);
    timeline = ScoreTimeline(doc);
    scheduler = ScoreAudioScheduler(
      engine: engine,
      track: track,
      autoTick: false,
    );
    scheduler
      ..setSpeed(1.0)
      ..beats = metronomeBeats(timeline)
      ..metronomeOn = true;
    scoreController = ScoreCubit(document: doc);
    final measures = timeline.measures;
    chords = chordsOf == null ? const [] : chordsOf!(track, timeline);
    practice = PracticeCubit(
      midiInput: midi,
      track: track,
      scheduler: scheduler,
      controller: scoreController,
      hand: Hand.direita,
      mode: mode,
      measureIndexAt: timeline.measureIndexAt,
      passOf: (i) => measures[i].pass,
      range: (
        startMs: measures[1].startMs.toDouble(),
        endMs: measures[3].startMs.toDouble(),
      ),
      onRangeDone: () => dones++,
      rewindOnError: true,
      measureSpanOf: (i) => (
        startMs: measures[i].startMs.toDouble(),
        endMs: measures[i].endMs.toDouble(),
      ),
      onRewind: (measure, startMs) => rewound.add((measure, startMs)),
      repeatNoticeDuration: const Duration(hours: 1),
      chordDemands: chords,
    );
  }

  /// As exigências de acorde da rodada, a partir da trilha e do tempo.
  final List<ChordDemand> Function(PerformanceTrack, ScoreTimeline)? chordsOf;
  final PracticeMode mode;
  final FakeSoundEngine engine = FakeSoundEngine();
  final FakeMidiInput midi = FakeMidiInput();
  late final List<ChordDemand> chords;
  late final PerformanceTrack track;
  late final ScoreTimeline timeline;
  late final ScoreAudioScheduler scheduler;
  late final ScoreCubit scoreController;
  late final PracticeCubit practice;
  int dones = 0;

  /// Cada volta da escada: o compasso e o instante musical do começo dele.
  final List<(int, double)> rewound = [];

  /// O estado da escada na tela.
  RepeatStatus? get status => practice.state.repeat;

  /// Deixa o aviso acabar e o degrau começar (o aviso não acaba sozinho).
  Future<void> settle() {
    practice.debugEndNotice();
    return Future<void>.value();
  }

  void dispose() {
    unawaited(practice.close());
    scoreController.clearAll();
    scoreController.close();
    midi.dispose();
  }

  /// Anda o relógio até [ms]. Para numa volta (o aviso segura a música).
  void advanceTo(double ms) {
    final voltas = rewound.length;
    var guard = 0;
    while (scheduler.isRunning &&
        rewound.length == voltas &&
        scheduler.positionMs < ms) {
      engine.now += 0.01;
      scheduler.pump();
      practice.debugTick();
      if (guard++ > 200000) throw StateError('não chegou a $ms ms');
    }
  }

  /// Tempo real (AC05b): toca o compasso [measure] no tempo. Cada nota do aluno
  /// sai no ataque dela, e em cada ataque de cifra as teclas do acorde (se
  /// [withChords]). [wrongAt] aperta uma tecla de fora do acorde nesse instante
  /// musical. Para se a escada volta.
  Future<void> playTimed(
    int measure, {
    bool withChords = true,
    double? wrongAt,
  }) async {
    final m = timeline.measures[measure];
    final keysAt = <double, List<int>>{};
    for (final e in track.events) {
      if (Hand.direita.studentStaves.contains(e.staff) &&
          !e.ornament &&
          e.onMs >= m.startMs &&
          e.onMs < m.endMs) {
        keysAt.putIfAbsent(e.onMs, () => []).add(e.pitch);
      }
    }
    if (withChords) {
      for (final chord in chords) {
        if (chord.onMs >= m.startMs && chord.onMs < m.endMs) {
          keysAt.putIfAbsent(chord.onMs, () => []).addAll(_cMajorKeys);
        }
      }
    }
    if (wrongAt != null) {
      keysAt.putIfAbsent(wrongAt, () => []).add(20);
    }
    final voltas = rewound.length;
    for (final at in keysAt.keys.toList()..sort()) {
      if (rewound.length != voltas) break;
      advanceTo(at);
      final keys = keysAt[at]!;
      for (final key in keys) {
        midi.press(key, atSeconds: engine.now);
      }
      await pumpEventQueue();
      for (final key in keys) {
        midi.release(key, atSeconds: engine.now);
      }
      await pumpEventQueue();
    }
  }

  /// Tempo real: anda até o fim do compasso [measure] mais uma folga, para o
  /// que ficou por tocar virar `missed` e o compasso ser decidido.
  void passEnd(int measure) =>
      advanceTo(timeline.measures[measure].endMs + 400);

  /// Anda até a contagem de um compasso acabar (a tela ainda a mostra).
  void runCountIn() {
    var guard = 0;
    while (status?.countingIn ?? false) {
      engine.now += 0.01;
      scheduler.pump();
      practice.debugTick();
      if (guard++ > 200000) throw StateError('a contagem não acabou');
    }
  }

  int measureOfStep() =>
      timeline.measureIndexAt(practice.currentStep.state!.onMs);

  /// Modo espera: toca os passos do compasso pendente até ele acabar (ou
  /// voltar). [wrongAt] aperta e solta uma tecla errada antes do passo de
  /// índice dado. O passo com acorde leva as teclas do acorde, além da melodia.
  Future<void> playMeasure({int? wrongAt}) async {
    final measure = measureOfStep();
    final voltas = rewound.length;
    var i = 0;
    var guard = 0;
    while (dones == 0 &&
        rewound.length == voltas &&
        practice.currentStep.state != null &&
        measureOfStep() == measure) {
      await _playStep(wrongFirst: i == wrongAt);
      i++;
      if (guard++ > 100) throw StateError('o compasso não acabou');
    }
  }

  Future<void> _playStep({bool wrongFirst = false}) async {
    final step = practice.currentStep.state!;
    advanceTo(step.onMs);
    if (wrongFirst) {
      midi.press(20, atSeconds: engine.now);
      await pumpEventQueue();
      midi.release(20, atSeconds: engine.now);
      await pumpEventQueue();
    }
    final keys = [
      for (final e in step.notes) e.pitch,
      if (step.chord != null) ..._cMajorKeys,
    ];
    for (final key in keys) {
      midi.press(key, atSeconds: engine.now);
    }
    await pumpEventQueue();
    for (final key in keys) {
      midi.release(key, atSeconds: engine.now);
    }
    await pumpEventQueue();
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('o acorde no modo espera (AC05a)', () {
    test('um acorde fecha o passo em qualquer inversão, com um só correct, sem '
        'eventId, com o ataque', () {
      for (final keys in [
        [48, 52, 55],
        [52, 55, 60],
        [55, 60, 64],
      ]) {
        final session = WaitModeSession([
          _chordStep(0, 1000, const _Chord(1000, _cMajor)),
        ]);
        final verdicts = _listen(session);
        for (final key in keys) {
          session.noteOn(key, atMs: 1000);
        }
        expect(session.done, isTrue, reason: '$keys');
        expect(verdicts, hasLength(1), reason: '$keys');
        expect(verdicts.single.kind, PracticeVerdictKind.correct);
        expect(verdicts.single.eventId, isNull);
        expect(verdicts.single.atMs, 1000);
        session.close();
      }
    });

    test('o acorde só fecha com as teclas presas ao mesmo tempo: soltar uma '
        'antes do fim a faz faltar de novo', () {
      final session = WaitModeSession([
        _chordStep(0, 1000, const _Chord(1000, _cMajor)),
      ]);
      session
        ..noteOn(48, atMs: 0)
        ..noteOn(52, atMs: 0);
      expect(session.done, isFalse);
      session.noteOff(52);
      session.noteOn(55, atMs: 0);
      expect(session.done, isFalse);
      session.noteOn(52, atMs: 0);
      expect(session.done, isTrue);
      session.close();
    });

    test('o acorde não tem janela de tempo: as teclas podem ser arpejadas, se '
        'ficam presas', () {
      final session = WaitModeSession([
        _chordStep(0, 1000, const _Chord(1000, _cMajor)),
      ]);
      session
        ..noteOn(48, atMs: 0)
        ..noteOn(52, atMs: 1000)
        ..noteOn(55, atMs: 2000);
      expect(session.done, isTrue);
      session.close();
    });

    test('tecla fora do acorde é erro na hora, com o ataque do passo, e segura '
        'o acorde até soltar', () {
      final session = WaitModeSession([
        _chordStep(0, 1000, const _Chord(1000, _cMajor)),
      ]);
      final verdicts = _listen(session);
      session.noteOn(62, atMs: 1010); // ré, fora de dó maior
      expect(verdicts.map((v) => v.kind), [PracticeVerdictKind.wrong]);
      expect(verdicts.single.atMs, 1000);
      expect(verdicts.single.eventId, isNull);
      session
        ..noteOff(62)
        ..noteOn(48, atMs: 1020)
        ..noteOn(52, atMs: 1020)
        ..noteOn(55, atMs: 1020);
      expect(session.done, isTrue);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.wrong,
        PracticeVerdictKind.correct,
      ]);
      session.close();
    });

    test('tecla errada segurada impede o acorde até soltar, mesmo com as três '
        'teclas certas presas', () {
      final session = WaitModeSession([
        _chordStep(0, 1000, const _Chord(1000, _cMajor)),
      ]);
      session
        ..noteOn(62, atMs: 1000)
        ..noteOn(48, atMs: 1000)
        ..noteOn(52, atMs: 1000)
        ..noteOn(55, atMs: 1000);
      expect(session.done, isFalse);
      session.noteOff(62);
      expect(session.done, isTrue);
      session.close();
    });

    test('melodia e acorde no mesmo ataque: só fecham com os dois, em qualquer '
        'ordem', () {
      // Acorde primeiro, melodia por último.
      var session = WaitModeSession([
        _mixedStep(0, 1000, 72, const _Chord(1000, _cMajor)),
      ]);
      var verdicts = _listen(session);
      session
        ..noteOn(48, atMs: 1000)
        ..noteOn(52, atMs: 1000)
        ..noteOn(55, atMs: 1000);
      expect(session.done, isFalse, reason: 'falta a melodia');
      session.noteOn(72, atMs: 1000);
      expect(session.done, isTrue);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct),
        hasLength(2),
        reason: 'a nota da melodia (com id) e o acorde (sem id)',
      );
      expect(
        verdicts.where((v) => v.eventId == 'm0').single.kind,
        PracticeVerdictKind.correct,
      );
      expect(verdicts.any((v) => v.eventId == null && v.atMs == 1000), isTrue);
      session.close();

      // Melodia primeiro, acorde depois.
      session = WaitModeSession([
        _mixedStep(0, 1000, 72, const _Chord(1000, _cMajor)),
      ]);
      verdicts = _listen(session);
      session.noteOn(72, atMs: 1000);
      expect(session.done, isFalse, reason: 'falta o acorde');
      session
        ..noteOn(48, atMs: 1000)
        ..noteOn(52, atMs: 1000);
      expect(session.done, isFalse);
      session.noteOn(55, atMs: 1000);
      expect(session.done, isTrue);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct),
        hasLength(2),
      );
      session.close();
    });

    test(
      'a nota de passagem da melodia, fora do acorde, não impede o acorde',
      () {
        // Lá (57), fora de dó maior, na melodia; o acorde fica embaixo.
        final session = WaitModeSession([
          _mixedStep(0, 1000, 57, const _Chord(1000, _cMajor)),
        ]);
        final verdicts = _listen(session);
        session
          ..noteOn(57, atMs: 1000)
          ..noteOn(48, atMs: 1000)
          ..noteOn(52, atMs: 1000)
          ..noteOn(55, atMs: 1000);
        expect(session.done, isTrue);
        expect(
          verdicts.where((v) => v.kind == PracticeVerdictKind.wrong),
          isEmpty,
        );
        session.close();
      },
    );

    test('a tecla já segurada antes do passo não conta para o acorde: soltar e '
        'apertar de novo conta', () {
      // Dois acordes iguais em seguida: o aluno não solta o primeiro.
      final session = WaitModeSession([
        _chordStep(0, 0, const _Chord(0, _cMajor)),
        _chordStep(1, 500, const _Chord(500, _cMajor)),
      ]);
      final verdicts = _listen(session);
      session
        ..noteOn(48, atMs: 0)
        ..noteOn(52, atMs: 0)
        ..noteOn(55, atMs: 0);
      expect(session.state!.index, 1);
      expect(session.done, isFalse);
      // As três continuam presas: nenhuma conta para o segundo acorde.
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct),
        hasLength(1),
      );
      session
        ..noteOff(52)
        ..noteOn(52, atMs: 500)
        ..noteOff(55)
        ..noteOn(55, atMs: 500);
      expect(session.done, isFalse, reason: 'o 48 ainda é do acorde anterior');
      session
        ..noteOff(48)
        ..noteOn(48, atMs: 500);
      expect(session.done, isTrue);
      session.close();
    });

    test('o passo publicado leva a exigência de acorde', () {
      const chord = _Chord(1000, _cMajor);
      final session = WaitModeSession([_chordStep(0, 1000, chord)]);
      expect(session.state!.chord, same(chord));
      session.noteOn(48, atMs: 1000);
      expect(session.state!.chord, same(chord));
      session.close();
    });

    test('sem demandas, o passo de melodia é o de antes: o veredito não leva '
        'ataque', () {
      final session = WaitModeSession([
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0)],
          remaining: {60},
        ),
      ]);
      final verdicts = _listen(session);
      expect(session.state!.chord, isNull);
      session.noteOn(62, atMs: 0);
      session.noteOff(62);
      session.noteOn(60, atMs: 0);
      expect(session.done, isTrue);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.wrong,
        PracticeVerdictKind.correct,
      ]);
      expect(verdicts.every((v) => v.atMs == null), isTrue);
      session.close();
    });
  });

  group('WaitModeSession.forStaves com acordes', () {
    test('a exigência cai no passo da melodia do mesmo ataque (até 1 ms), e '
        'quem não tem nota ganha passo só dela; o que já vale sem tecla fica de '
        'fora', () {
      final track = PerformanceTrack.fromEvents([
        _ev('m1', 72, 1000),
        _ev('m2', 74, 2000),
      ]);
      final session = WaitModeSession.forStaves(
        track,
        staves: {1},
        chords: [
          const _Chord(1000.4, _cMajor),
          const _Chord(1500, _cMajor),
          const _Free(1700),
        ],
      );
      expect(session.state!.onMs, 1000);
      expect(session.state!.notes.single.pitch, 72);
      expect(session.state!.chord, isNotNull);

      // A melodia sozinha não fecha o passo do acorde.
      session.noteOn(72, atMs: 1000);
      expect(session.state!.onMs, 1000);
      session
        ..noteOn(48, atMs: 1000)
        ..noteOn(52, atMs: 1000)
        ..noteOn(55, atMs: 1000);
      session
        ..noteOff(72)
        ..noteOff(48)
        ..noteOff(52)
        ..noteOff(55);

      // Passo só de acorde, em 1500: sem nota, e o de 1700 não existe.
      expect(session.state!.onMs, 1500);
      expect(session.state!.notes, isEmpty);
      session
        ..noteOn(48, atMs: 1500)
        ..noteOn(52, atMs: 1500)
        ..noteOn(55, atMs: 1500);
      session
        ..noteOff(48)
        ..noteOff(52)
        ..noteOff(55);

      expect(session.state!.onMs, 2000);
      expect(session.state!.chord, isNull);
      session.noteOn(74, atMs: 2000);
      expect(session.done, isTrue);
      session.close();
    });

    test('duas exigências no mesmo passo são erro de quem monta a rodada', () {
      final track = PerformanceTrack.fromEvents([_ev('m1', 72, 1000)]);
      expect(
        () => WaitModeSession.forStaves(
          track,
          staves: {1},
          chords: [const _Chord(1000, _cMajor), const _Chord(1000.5, _cMajor)],
        ),
        throwsArgumentError,
      );
    });

    test('sem exigências, o passo é o mesmo de antes (nenhum acorde)', () {
      final track = PerformanceTrack.fromEvents([_ev('m1', 72, 1000)]);
      final session = WaitModeSession.forStaves(track, staves: {1});
      expect(session.state!.chord, isNull);
      expect(session.state!.onMs, 1000);
      session.close();
    });
  });

  group('a escada com acorde (AC05a)', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test('sem acordes, o compasso certo não volta', () async {
      rig = _Rig();
      rig.practice.start();
      await rig.playMeasure();
      await rig.playMeasure();
      expect(rig.dones, 1);
      expect(rig.rewound, isEmpty);
      expect(rig.practice.stageResult!.badMeasures, isEmpty);
    });

    test(
      'a melodia sozinha não fecha o passo de acorde: a música para nele',
      () async {
        rig = _Rig(chordsOf: _measureOneChords);
        rig.practice.start();
        final first = rig.practice.currentStep.state!;
        rig.advanceTo(first.onMs);
        for (final e in first.notes) {
          rig.midi.press(e.pitch, atSeconds: rig.engine.now);
        }
        await pumpEventQueue();
        expect(rig.practice.currentStep.state!.index, first.index);
        for (final key in _cMajorKeys) {
          rig.midi.press(key, atSeconds: rig.engine.now);
        }
        await pumpEventQueue();
        expect(rig.practice.currentStep.state!.index, isNot(first.index));
      },
    );

    test(
      'tecla fora do acorde no compasso 1: o compasso acaba, aviso, e repete; '
      'certo, segue',
      () async {
        rig = _Rig(chordsOf: _measureOneChords);
        final start1 = rig.timeline.measures[1].startMs.toDouble();
        rig.practice.start();
        await rig.playMeasure(wrongAt: 0);
        expect(rig.rewound, [(1, start1)]);
        expect(rig.status!.notice, RepeatNotice.missed);
        await rig.settle();
        // A repetição começa no primeiro passo do compasso, e o acorde volta a
        // pedir as teclas dele.
        expect(rig.measureOfStep(), 1);
        await rig.playMeasure();
        expect(rig.practice.rewinds, {1: 1});
        await rig.playMeasure();
        expect(rig.dones, 1);
        final result = rig.practice.stageResult!;
        expect(result.rewinds, {1: 1});
        expect(result.badMeasures, {1});
      },
    );
  });

  group('o acorde no tempo real (AC05b)', () {
    /// As sessões de tempo real que o teste ouve, com os acordes [chords].
    RealtimeSession rt(List<ChordDemand> chords, {List<SoundEvent>? events}) =>
        RealtimeSession(events ?? const [], speed: 1, chords: chords);

    /// Os vereditos de [session], na ordem, desde agora.
    List<NoteVerdict> listenRt(RealtimeSession session) {
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);
      return verdicts;
    }

    test('um acorde com as três teclas na janela é correct, sem eventId, com o '
        'ataque; o veredito sai só no fim da janela', () {
      final session = rt(const [_Chord(1000, _cMajor)]);
      final verdicts = listenRt(session);
      session
        ..noteOn(48, 1010)
        ..noteOn(52, 1020)
        ..noteOn(55, 1030);
      expect(verdicts, isEmpty, reason: 'a janela ainda não fechou');
      expect(session.hasPendingIn(950, 1050), isTrue);
      session.tick(1151);
      expect(verdicts.map((v) => v.kind), [PracticeVerdictKind.correct]);
      expect(verdicts.single.eventId, isNull);
      expect(verdicts.single.atMs, 1000);
      expect(verdicts.single.deltaMs, 10, reason: 'o primeiro toque');
      expect(session.hasPendingIn(950, 1050), isFalse);
      session.dispose();
    });

    test('o primeiro toque fora da janela de certo, mas dentro da máxima, é '
        'late ou early, como a nota', () {
      var session = rt(const [_Chord(1000, _cMajor)]);
      var verdicts = listenRt(session);
      session
        ..noteOn(48, 1100)
        ..noteOn(52, 1100)
        ..noteOn(55, 1100)
        ..tick(1200);
      expect(verdicts.single.kind, PracticeVerdictKind.late);
      expect(verdicts.single.deltaMs, 100);
      session.dispose();

      session = rt(const [_Chord(1000, _cMajor)]);
      verdicts = listenRt(session);
      session
        ..noteOn(48, 900)
        ..noteOn(52, 900)
        ..noteOn(55, 900)
        ..tick(1200);
      expect(verdicts.single.kind, PracticeVerdictKind.early);
      expect(verdicts.single.deltaMs, -100);
      session.dispose();
    });

    test('a janela fecha sem o acorde: missed no ataque, e a tecla depois dela '
        'é wrong', () {
      final session = rt(const [_Chord(1000, _cMajor)]);
      final verdicts = listenRt(session);
      session
        ..noteOn(48, 1200)
        ..noteOn(52, 1200)
        ..noteOn(55, 1200);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.missed,
        PracticeVerdictKind.wrong,
        PracticeVerdictKind.wrong,
        PracticeVerdictKind.wrong,
      ]);
      expect(verdicts.first.atMs, 1000);
      expect(verdicts.skip(1).every((v) => v.atMs == 1200), isTrue);
      session.dispose();

      final silent = rt(const [_Chord(1000, _cMajor)]);
      final silentVerdicts = listenRt(silent);
      silent.tick(1200);
      expect(silentVerdicts.map((v) => v.kind), [PracticeVerdictKind.missed]);
      silent.dispose();
    });

    test(
      'tecla do acorde que chega antes da janela abrir é wrong; o acorde '
      'segue aberto e conta se as teclas forem apertadas de novo na janela',
      () {
        final session = rt(const [_Chord(1000, _cMajor)]);
        final verdicts = listenRt(session);
        session.noteOn(48, 800);
        expect(verdicts.map((v) => v.kind), [PracticeVerdictKind.wrong]);
        expect(verdicts.single.atMs, 800, reason: 'o instante da tecla');
        expect(session.hasPendingIn(950, 1050), isTrue, reason: 'ainda aberto');
        session
          ..noteOn(48, 1000)
          ..noteOn(52, 1000)
          ..noteOn(55, 1000)
          ..tick(1200);
        expect(verdicts.map((v) => v.kind), [
          PracticeVerdictKind.wrong,
          PracticeVerdictKind.correct,
        ]);
        session.dispose();
      },
    );

    test('tecla de fora do acorde é wrong no compasso dela (o instante da '
        'tecla), e não tira o acorde', () {
      final session = rt(const [_Chord(1000, _cMajor)]);
      final verdicts = listenRt(session);
      session
        ..noteOn(62, 1050)
        ..noteOn(48, 1060)
        ..noteOn(52, 1060)
        ..noteOn(55, 1060)
        ..tick(1200);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.wrong,
        PracticeVerdictKind.correct,
      ]);
      expect(verdicts.first.eventId, isNull);
      expect(verdicts.first.atMs, 1050);
      session.dispose();
    });

    test('a tecla presa desde o acorde anterior não conta para o seguinte: é '
        'preciso apertá-la de novo na janela', () {
      // O aluno segura dó maior de 1000 a 1500 e não aperta nada no 1500.
      var session = rt(const [_Chord(1000, _cMajor), _Chord(1500, _cMajor)]);
      var verdicts = listenRt(session);
      session
        ..noteOn(48, 1000)
        ..noteOn(52, 1000)
        ..noteOn(55, 1000)
        ..tick(1700);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.correct,
        PracticeVerdictKind.missed,
      ]);
      expect(verdicts.last.atMs, 1500);
      session.dispose();

      // Soltou e apertou de novo na janela do segundo: conta.
      session = rt(const [_Chord(1000, _cMajor), _Chord(1500, _cMajor)]);
      verdicts = listenRt(session);
      session
        ..noteOn(48, 1000)
        ..noteOn(52, 1000)
        ..noteOn(55, 1000)
        ..noteOn(48, 1500)
        ..noteOn(52, 1500)
        ..noteOn(55, 1500)
        ..tick(1700);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.correct,
        PracticeVerdictKind.correct,
      ]);
      expect(verdicts.last.atMs, 1500);
      session.dispose();
    });

    test('melodia e acorde no mesmo ataque: cada um sai no seu veredito, e a '
        'nota da melodia que é do acorde conta para os dois', () {
      final session = rt(
        const [_Chord(1000, _cMajor)],
        events: [_ev('m', 72, 1000)],
      );
      final verdicts = listenRt(session);
      session
        ..noteOn(72, 1000)
        ..noteOn(48, 1000)
        ..noteOn(52, 1000)
        ..noteOn(55, 1000)
        ..tick(1200);
      expect(verdicts, hasLength(2));
      expect(
        verdicts.firstWhere((v) => v.eventId == 'm').kind,
        PracticeVerdictKind.correct,
      );
      expect(
        verdicts.where((v) => v.eventId == null).single.kind,
        PracticeVerdictKind.correct,
      );
      session.dispose();
    });

    test(
      'a nota de passagem da melodia, fora do acorde, não tira o acorde',
      () {
        final session = rt(
          const [_Chord(1000, _cMajor)],
          events: [_ev('p', 57, 1000)],
        );
        final verdicts = listenRt(session);
        session
          ..noteOn(57, 1000)
          ..noteOn(48, 1000)
          ..noteOn(52, 1000)
          ..noteOn(55, 1000)
          ..tick(1200);
        expect(verdicts.map((v) => v.kind), [
          PracticeVerdictKind.correct,
          PracticeVerdictKind.correct,
        ]);
        expect(verdicts.first.eventId, 'p');
        session.dispose();
      },
    );

    test('sem janela adaptativa, o acorde aceita a tecla 140 ms antes; com ela, '
        'o acorde vizinho encolhe a janela e a tecla fica de fora', () {
      // Dó maior em 1000, e ré menor (outro acorde) em 900: a tecla de dó (48)
      // em 860 é do primeiro acorde, mas só cai nele se a janela não encolher.
      const neighbour = _Chord(900, {2, 5, 9});
      final fixed = rt(const [neighbour, _Chord(1000, _cMajor)]);
      var verdicts = listenRt(fixed);
      fixed
        ..noteOn(48, 860)
        ..noteOn(52, 860)
        ..noteOn(55, 860)
        ..tick(1200);
      expect(
        verdicts.where((v) => v.atMs == 1000).single.kind,
        PracticeVerdictKind.early,
      );
      fixed.dispose();

      final adaptive = RealtimeSession(
        const [],
        speed: 1,
        adaptiveWindow: true,
        chords: const [neighbour, _Chord(1000, _cMajor)],
      );
      verdicts = listenRt(adaptive);
      adaptive
        ..noteOn(48, 860)
        ..noteOn(52, 860)
        ..noteOn(55, 860)
        ..tick(1200);
      expect(
        verdicts.where((v) => v.atMs == 1000).single.kind,
        PracticeVerdictKind.missed,
      );
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.wrong),
        hasLength(3),
      );
      adaptive.dispose();
    });

    test('com forgiveSounding, a tecla que soa de uma nota da melodia não é '
        'wrong; sem ele, é', () {
      // Uma nota de dó (48) soa de 0 a 400; o aluno a toca de novo em 300.
      final events = [_ev('m', 48, 0)];
      final forgiving = RealtimeSession(
        events,
        speed: 1,
        forgiveSounding: true,
        chords: const [_Chord(1000, _cMajor)],
      );
      var verdicts = listenRt(forgiving);
      forgiving.noteOn(48, 300);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.wrong),
        isEmpty,
      );
      forgiving.dispose();

      final plain = rt(const [_Chord(1000, _cMajor)], events: events);
      verdicts = listenRt(plain);
      plain.noteOn(48, 300);
      expect(verdicts.single.kind, PracticeVerdictKind.wrong);
      plain.dispose();
    });

    test('um ataque que já vale sem tecla (o N.C.) não se cobra e não deixa o '
        'compasso aberto', () {
      final session = rt(const [_Free(1000)]);
      final verdicts = listenRt(session);
      expect(session.hasPendingIn(950, 1050), isFalse);
      expect(session.firstPendingOnMs, isNull);
      session.tick(2000);
      expect(verdicts, isEmpty);
      session.dispose();
    });

    test('firstPendingOnMs vê o acorde até a janela dele fechar', () {
      final session = rt(
        const [_Chord(500, _cMajor)],
        events: [_ev('n', 60, 800)],
      );
      expect(session.firstPendingOnMs, 500);
      session.tick(700);
      expect(session.firstPendingOnMs, 800);
      session.dispose();
    });

    test('resetTo reabre o acorde do trecho, e a tecla do acorde do trecho '
        'seguinte, tocada perto do fim, não é wrong deste', () {
      final session = rt(const [_Chord(1000, _cMajor), _Chord(1300, _cMajor)]);
      final verdicts = listenRt(session);
      session
        ..noteOn(48, 1000)
        ..noteOn(52, 1000)
        ..noteOn(55, 1000)
        ..tick(1200);
      expect(verdicts.map((v) => v.kind), [PracticeVerdictKind.correct]);

      // A escada volta ao 1000 e o trecho acaba em 1100: o de 1300 é do que vem.
      session.resetTo(1000, untilMs: 1100);
      expect(session.hasPendingIn(990, 1010), isTrue, reason: 'reaberto');
      session
        ..noteOn(48, 1000)
        ..noteOn(52, 1000)
        ..noteOn(55, 1000)
        ..noteOn(48, 1200)
        ..tick(1400);
      expect(verdicts.map((v) => v.kind), [
        PracticeVerdictKind.correct,
        PracticeVerdictKind.correct,
      ]);
      session.dispose();
    });

    test(
      'sem demandas, a sessão é a de antes: o erro leva o instante da tecla, '
      'e o acerto e o perdido saem como sempre',
      () {
        final session = RealtimeSession([
          _ev('a', 60, 1000),
          _ev('b', 62, 2000),
        ], speed: 1);
        final verdicts = listenRt(session);
        session
          ..noteOn(60, 1000)
          ..noteOn(64, 1500)
          ..tick(2500);
        expect(verdicts.map((v) => v.kind), [
          PracticeVerdictKind.correct,
          PracticeVerdictKind.wrong,
          PracticeVerdictKind.missed,
        ]);
        expect(verdicts[0].eventId, 'a');
        expect(verdicts[0].atMs, isNull);
        expect(verdicts[1].atMs, 1500);
        expect(verdicts[2].eventId, 'b');
        expect(verdicts[2].atMs, isNull);
        session.dispose();
      },
    );
  });

  group('a escada com acorde no tempo real (AC05b)', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test(
      'tempo real, com todos os acordes certos: a rodada passa sem volta',
      () async {
        rig = _Rig(chordsOf: _measureOneChords, mode: PracticeMode.realtime);
        rig.practice.start();
        await rig.playTimed(1);
        await rig.playTimed(2, withChords: false);
        rig.passEnd(2);
        expect(rig.dones, 1);
        expect(rig.rewound, isEmpty);
        final result = rig.practice.stageResult!;
        expect(result.badMeasures, isEmpty);
        expect(result.percent, 100);
      },
    );

    test('tempo real: o acorde perdido no compasso 1 repete o compasso, e o '
        'degrau reabre o acorde', () async {
      rig = _Rig(chordsOf: _measureOneChords, mode: PracticeMode.realtime);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      await rig.playTimed(1, withChords: false);
      rig.passEnd(1);
      expect(rig.rewound, [(1, start1)]);
      expect(rig.status!.notice, RepeatNotice.missed);
      await rig.settle();
      // O primeiro degrau da escada é o "só notas" (modo espera): o acorde pede
      // as teclas dele, e acertando, sobe ao de tempo real com contagem.
      expect(rig.status!.rung.isWait, isTrue);
      await rig.playMeasure();
      expect(rig.status!.notice, RepeatNotice.passed);
      await rig.settle();
      rig.runCountIn();
      // O degrau de tempo real reabriu o acorde: ele conta de novo. Cada degrau
      // que começa conta uma volta (o "só notas" e o de tempo real).
      await rig.playTimed(1);
      rig.passEnd(1);
      expect(rig.status, isNull);
      expect(rig.practice.rewinds, {1: 2});
      await rig.playTimed(2, withChords: false);
      rig.passEnd(2);
      expect(rig.dones, 1);
      final result = rig.practice.stageResult!;
      expect(result.rewinds, {1: 2});
      expect(result.badMeasures, {1});
    });

    test('tempo real: tecla de fora do acorde no compasso 1 é erro desse '
        'compasso, e a escada o repete', () async {
      rig = _Rig(chordsOf: _measureOneChords, mode: PracticeMode.realtime);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      await rig.playTimed(1, wrongAt: start1 + 300);
      rig.passEnd(1);
      expect(rig.rewound, [(1, start1)]);
      await rig.settle();
      await rig.playMeasure();
      await rig.settle();
      rig.runCountIn();
      await rig.playTimed(1);
      rig.passEnd(1);
      await rig.playTimed(2, withChords: false);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.practice.stageResult!.badMeasures, {1});
    });
  });
}

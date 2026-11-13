// LP24.2 / LP25 — A volta na hora no `PracticeController`: o compasso que acaba
// com erro não segue; ele repete numa escada de degraus (só notas, depois os
// andamentos até o da etapa), com aviso de "Errou" e de "Acertou" e contagem de
// um compasso antes de cada degrau que sobe. Mesmo arranjo de
// test/practice_controller_test.dart: agendador de verdade sobre um motor falso,
// o relógio andado à mão.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/metronome.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_comum/practice/hand.dart';
import 'package:zywny_comum/practice/measure_rewind.dart';
import 'package:zywny_comum/practice/practice_controller.dart';
import 'package:zywny_diag/diag_log.dart';

import 'support/practice_fakes.dart';

VsbDocument _loadDoc() => VsbDocument.fromBytes(
  Uint8List.fromList(File('test/fixtures/erik-satie.vsb').readAsBytesSync()),
);

/// Uma rodada montada: o controlador e o que o teste precisa para tocar.
///
/// O aviso da escada não acaba sozinho: o teste o encerra com [settle], e o
/// compasso repete depois dele. As batidas da rodada são as do
/// timemap, então a contagem de um compasso existe de verdade.
class _Rig {
  _Rig({
    required this.mode,
    required this.firstMeasure,
    required this.endMeasure,
    this.skipMeasure,
    this.speed = 1.0,
    this.repeatSpeeds = const [],
    this.noticeDuration = const Duration(hours: 1),
  }) {
    final doc = _loadDoc();
    track = PerformanceTrack.fromDocument(doc);
    timeline = ScoreTimeline(doc);
    scheduler = ScoreAudioScheduler(
      engine: engine,
      track: track,
      autoTick: false,
    );
    scheduler
      ..setSpeed(speed)
      ..beats = metronomeBeats(timeline);
    scoreController = ScoreController(document: doc);
    final measures = timeline.measures;
    final skip = skipMeasure;
    practice = PracticeController(
      midiInput: midi,
      track: track,
      scheduler: scheduler,
      controller: scoreController,
      hand: Hand.direita,
      mode: mode,
      measureIndexAt: timeline.measureIndexAt,
      passOf: (i) => measures[i].pass,
      range: (
        startMs: measures[firstMeasure].startMs.toDouble(),
        endMs: measures[endMeasure].startMs.toDouble(),
      ),
      rangeJumps: [
        if (skip != null)
          (
            startMs: measures[skip].startMs.toDouble(),
            endMs: measures[skip].endMs.toDouble(),
          ),
      ],
      onRangeDone: () => dones++,
      rewindOnError: true,
      measureSpanOf: (i) => (
        startMs: measures[i].startMs.toDouble(),
        endMs: measures[i].endMs.toDouble(),
      ),
      onRewind: (measure, startMs) {
        rewound.add((measure, startMs));
        rewoundAt.add(engine.now);
      },
      repeatSpeeds: repeatSpeeds,
      repeatNoticeDuration: noticeDuration,
    );
    // Cada nota do app que o agendador manda ao motor, com o instante musical
    // dela (lido com a âncora de agora, que vale para este lote).
    engine.onSchedule = (events) {
      for (final e in events) {
        if (e.status & 0xF0 == 0x90 && e.d2 > 0) {
          noteOns.add((
            at: e.at,
            pitch: e.d1,
            musical: scheduler.musicalAtDevice(e.at),
          ));
        }
      }
    };
  }

  final PracticeMode mode;
  final int firstMeasure;
  final int endMeasure;
  final int? skipMeasure;
  final double speed;
  final List<double> repeatSpeeds;
  final Duration noticeDuration;
  final FakeSoundEngine engine = FakeSoundEngine();
  final FakeMidiInput midi = FakeMidiInput();
  late final PerformanceTrack track;
  late final ScoreTimeline timeline;
  late final ScoreAudioScheduler scheduler;
  late final ScoreController scoreController;
  late final PracticeController practice;
  int dones = 0;

  /// Cada volta da escada (o aviso que segura a música no começo do compasso),
  /// na ordem: o compasso e o instante musical dele.
  final List<(int, double)> rewound = [];

  /// O instante do motor (segundos) de cada volta, na ordem de [rewound].
  final List<double> rewoundAt = [];

  /// As notas do app agendadas ao motor (ataques), com o instante e o tempo
  /// musical de cada uma.
  final List<({double at, int pitch, double musical})> noteOns = [];

  /// O estado da escada na tela.
  RepeatStatus? get status => practice.repeat.value;

  /// Deixa o aviso acabar e o degrau começar. O aviso não acaba sozinho (o
  /// tempo dele é de horas): só aqui, quando o teste quer.
  Future<void> settle() {
    practice.debugEndNotice();
    return Future<void>.value();
  }

  /// As notas do app (a pauta que o app toca) que começam de [fromMs] até
  /// [toMs]. Uma folga de 1 ms na fronteira: o Verovio arredonda o começo do
  /// compasso, e a nota da barra (ex.: 4736,83 ms para o compasso em 4737) é
  /// a do compasso que começa ali.
  List<SoundEvent> appNotesFrom(double fromMs, double toMs) => [
    for (final e in track.events)
      if (Hand.direita.appStaves.contains(e.staff) &&
          e.onMs >= fromMs - 1 &&
          e.onMs < toMs - 1)
        e,
  ];

  /// As notas do app do compasso [measure].
  List<SoundEvent> appNotesOf(int measure) {
    final m = timeline.measures[measure];
    return appNotesFrom(m.startMs.toDouble(), m.endMs.toDouble());
  }

  /// As notas do app que começam no compasso seguinte a [measure] e que o
  /// motor já tinha recebido até a primeira volta (com `at` até o instante
  /// dela). Se a volta é do compasso [measure], essas notas não podiam soar.
  List<({double at, int pitch, double musical})> appSoundedAfter(int measure) {
    final boundary = timeline.measures[measure].endMs - 1.0;
    final until = rewoundAt.isEmpty ? double.infinity : rewoundAt.first;
    return [
      for (final n in noteOns)
        if (n.at <= until && n.musical >= boundary) n,
    ];
  }

  void dispose() {
    practice.dispose();
    scoreController.clearAll();
    scoreController.dispose();
    midi.dispose();
  }

  /// As notas do aluno (mão direita) do compasso [measure].
  List<SoundEvent> notesOf(int measure) {
    final m = timeline.measures[measure];
    return [
      for (final e in track.events)
        if (Hand.direita.studentStaves.contains(e.staff) &&
            !e.ornament &&
            e.onMs >= m.startMs &&
            e.onMs < m.endMs)
          e,
    ];
  }

  /// Anda o relógio até [ms]. Para numa volta (o aviso segura a música: o
  /// agendador para e a posição não anda mais).
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

  /// Tempo real: toca o compasso [measure] no tempo; [miss] fica sem tocar
  /// (vira perdida).
  Future<void> playTimed(int measure, {int? miss}) async {
    final notes = notesOf(measure);
    for (var i = 0; i < notes.length; i++) {
      if (i == miss) continue;
      advanceTo(notes[i].onMs);
      midi.press(notes[i].pitch, atSeconds: engine.now);
      await pumpEventQueue();
    }
  }

  /// Tempo real: anda até o fim do compasso [measure] mais a folga.
  void passEnd(int measure) =>
      advanceTo(timeline.measures[measure].endMs + 400);

  /// Modo espera: toca o passo pendente; [wrongFirst] aperta e solta uma
  /// tecla errada antes.
  Future<void> playStep({bool wrongFirst = false}) async {
    final step = practice.currentStep.value!;
    advanceTo(step.onMs);
    if (wrongFirst) {
      midi.press(20, atSeconds: engine.now);
      await pumpEventQueue();
      midi.release(20, atSeconds: engine.now);
      await pumpEventQueue();
    }
    for (final e in step.notes) {
      midi.press(e.pitch, atSeconds: engine.now);
    }
    await pumpEventQueue();
    for (final e in step.notes) {
      midi.release(e.pitch, atSeconds: engine.now);
    }
    await pumpEventQueue();
  }

  int measureOfStep() =>
      timeline.measureIndexAt(practice.currentStep.value!.onMs);

  /// Modo espera: toca os passos do compasso pendente até ele acabar (ou
  /// voltar); [wrongAt] erra o passo de índice dado no compasso.
  Future<void> playWaitMeasure({int? wrongAt}) async {
    final measure = measureOfStep();
    final voltas = rewound.length;
    var i = 0;
    while (dones == 0 &&
        rewound.length == voltas &&
        practice.currentStep.value != null &&
        measureOfStep() == measure) {
      await playStep(wrongFirst: i == wrongAt);
      i++;
    }
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('MeasureRewinds', () {
    test('erro marca; a volta conta e zera o compasso e o que vem depois', () {
      final book = MeasureRewinds();
      expect(book.hasError(2), isFalse);
      book
        ..error(2)
        ..error(3);
      expect(book.hasError(2), isTrue);
      expect(book.rewind(2), 2);
      expect(book.hasError(2), isFalse);
      expect(book.hasError(3), isFalse);
      book.error(2);
      expect(book.rewind(2), 3);
      expect(book.counts, {2: 2});
    });
  });

  group('volta na hora, tempo real: a escada de repetição', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test('compasso certo não volta e não há escada', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.rewound, isEmpty);
      expect(rig.status, isNull);
      expect(rig.practice.stageResult!.rewinds, isEmpty);
      expect(rig.practice.report.wrong + rig.practice.report.missed, 0);
    });

    test('erro: o aviso segura a música no começo do compasso; depois o '
        'compasso repete só notas, e acertando sobe com contagem ao andamento '
        'da etapa', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      // O aviso de "Errou": a música parada no começo do compasso, sem contar.
      expect(rig.status!.notice, RepeatNotice.missed);
      expect(rig.rewound, [(1, start1)]);
      expect(rig.scheduler.isRunning, isFalse);
      expect(rig.practice.rewinds, isEmpty, reason: 'a repetição ainda não');
      // Depois do aviso, o degrau "só notas": sem contagem, o aluno toca.
      await rig.settle();
      expect(rig.status!.notice, RepeatNotice.none);
      expect(rig.status!.rung.isWait, isTrue);
      expect(rig.status!.countingIn, isFalse);
      expect(rig.scheduler.isRunning, isTrue);
      expect(rig.practice.rewinds, {1: 1});
      await rig.playWaitMeasure();
      // Acertou num degrau que não é o último: aviso, e a contagem antes do 100%.
      expect(rig.status!.notice, RepeatNotice.passed);
      expect(rig.status!.rung.isWait, isFalse);
      expect(rig.rewound, hasLength(2));
      await rig.settle();
      expect(rig.status!.countingIn, isTrue);
      expect(rig.scheduler.isCountingIn, isTrue);
      // Durante a contagem a tecla não conta.
      rig.midi.press(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      rig.midi.release(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      expect(rig.practice.wrongMarks, isEmpty);
      rig.runCountIn();
      expect(rig.status!.countingIn, isFalse);
      // Acertou no último degrau: a escada acaba e a música segue.
      await rig.playTimed(1);
      rig.passEnd(1);
      expect(rig.status, isNull);
      expect(rig.practice.rewinds, {1: 2});
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.rewound, hasLength(2));
      final result = rig.practice.stageResult!;
      expect(result.rewinds, {1: 2});
      expect(result.badMeasures, contains(1));
    });

    test('erro no degrau de 50% volta ao só notas, não ao degrau de baixo; a '
        'música segue no andamento da etapa de 75%', () async {
      rig = _Rig(
        mode: PracticeMode.realtime,
        firstMeasure: 1,
        endMeasure: 3,
        speed: 0.75,
        repeatSpeeds: const [0.5, 0.75, 0.9, 1.0],
      );
      rig.practice.start();
      // Etapa de 75%: a escada é só notas, 50%, 75%.
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.status!.rungCount, 3);
      await rig.settle();
      await rig.playWaitMeasure();
      await rig.settle();
      rig.runCountIn();
      // Degrau 50%: o andamento do agendador é o do degrau.
      expect(rig.status!.rung.speed, 0.5);
      expect(rig.scheduler.speed, 0.5);
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      // Errou a 50%: aviso, e a volta é ao só notas (o degrau 1).
      expect(rig.status!.notice, RepeatNotice.missed);
      expect(rig.status!.rungIndex, 0);
      await rig.settle();
      expect(rig.status!.rung.isWait, isTrue);
      await rig.playWaitMeasure();
      await rig.settle();
      rig.runCountIn();
      await rig.playTimed(1);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      // Acertou a 50%: sobe ao 75%, que é o andamento da etapa.
      expect(rig.status!.rung.speed, 0.75);
      await rig.settle();
      rig.runCountIn();
      expect(rig.scheduler.speed, 0.75);
      await rig.playTimed(1);
      rig.passEnd(1);
      expect(rig.status, isNull);
      expect(rig.scheduler.speed, 0.75);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      // Cinco repetições: só notas, 50%, só notas, 50%, 75%.
      expect(rig.practice.stageResult!.rewinds, {1: 5});
    });

    test('pausar durante o aviso: o degrau espera a retomada', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      rig.practice.pause();
      await rig.settle();
      // Pausada, o compasso não repete.
      expect(rig.status!.notice, RepeatNotice.missed);
      expect(rig.scheduler.isRunning, isFalse);
      expect(rig.practice.rewinds, isEmpty);
      rig.practice.resume();
      expect(rig.scheduler.isRunning, isTrue);
      expect(rig.status!.notice, RepeatNotice.none);
      expect(rig.practice.rewinds, {1: 1});
    });

    test(
      'parar no aviso solta a escada: o compasso não repete depois',
      () async {
        rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
        rig.practice.start();
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        expect(rig.status, isNotNull);
        rig.practice.stop();
        expect(rig.status, isNull);
        await rig.settle();
        expect(rig.practice.rewinds, isEmpty);
        expect(rig.scheduler.isRunning, isFalse);
      },
    );

    test('a primeira nota do compasso, tocada logo que a contagem acaba, conta '
        '(antes o tick ainda não tinha soltado a escada)', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      await rig.settle();
      await rig.playWaitMeasure();
      await rig.settle();
      expect(rig.scheduler.isCountingIn, isTrue);
      // Anda o motor até a contagem acabar, sem passar pelo tick do controlador.
      while (rig.scheduler.isCountingIn) {
        rig.engine.now += 0.01;
        rig.scheduler.pump();
      }
      final first = rig.notesOf(1).first;
      while (rig.scheduler.positionMs < first.onMs) {
        rig.engine.now += 0.01;
        rig.scheduler.pump();
      }
      final before = rig.practice.report.correct;
      rig.midi.press(first.pitch, atSeconds: rig.engine.now);
      await pumpEventQueue();
      expect(rig.practice.report.correct, before + 1);
    });

    test('degrau de tempo real: a primeira nota do compasso seguinte, tocada '
        'um pouco antes, não é erro do compasso que repete', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      await rig.settle();
      await rig.playWaitMeasure();
      await rig.settle();
      rig.runCountIn();
      await rig.playTimed(1);
      final next = rig.notesOf(2).first;
      rig.advanceTo(next.onMs - 8);
      rig.midi.press(next.pitch, atSeconds: rig.engine.now);
      await pumpEventQueue();
      rig.passEnd(1);
      expect(rig.status, isNull, reason: 'o degrau acertou e a escada acabou');
      expect(rig.rewound, hasLength(2));
    });

    test('aviso em 0 s: nada aparece e o degrau começa na hora', () async {
      rig = _Rig(
        mode: PracticeMode.realtime,
        firstMeasure: 1,
        endMeasure: 3,
        noticeDuration: Duration.zero,
      );
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.rewound, isNotEmpty);
      expect(rig.status!.notice, RepeatNotice.none);
      await pumpEventQueue();
      expect(rig.practice.rewinds, {1: 1}, reason: 'o degrau já começou');
    });

    test('a tecla tocada durante o aviso não conta', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      final wrongBefore = rig.practice.wrongMarks.length;
      rig.midi.press(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      rig.midi.release(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      expect(rig.practice.wrongMarks.length, wrongBefore);
      expect(rig.practice.report.wrong, 0);
    });

    test(
      'a escada sobe degrau a degrau até o 90%; errar ali volta ao só notas',
      () async {
        rig = _Rig(
          mode: PracticeMode.realtime,
          firstMeasure: 1,
          endMeasure: 3,
          repeatSpeeds: const [0.5, 0.75, 0.9],
        );
        rig.practice.start();
        // Escada: só notas, 50%, 75%, 90%, 100%.
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        expect(rig.status!.rungCount, 5);
        await rig.settle();
        await rig.playWaitMeasure();
        await rig.settle();
        rig.runCountIn();
        expect(rig.status!.rung.speed, 0.5);
        await rig.playTimed(1);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        await rig.settle();
        rig.runCountIn();
        expect(rig.status!.rung.speed, 0.75);
        await rig.playTimed(1);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        await rig.settle();
        rig.runCountIn();
        expect(rig.status!.rung.speed, 0.9);
        expect(rig.scheduler.speed, 0.9);
        // Errou a 90%: aviso, e a volta é ao só notas.
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        expect(rig.status!.notice, RepeatNotice.missed);
        await rig.settle();
        expect(rig.status!.rung.isWait, isTrue);
        expect(rig.status!.rungIndex, 0);
      },
    );

    test('tempo real: nota perdida no começo do compasso não deixa nota do '
        'compasso seguinte soar', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.rewound, isNotEmpty);
      expect(rig.appSoundedAfter(1), isEmpty);
    });

    test('a última nota perdida, que só fecha depois da barra, volta; a nota '
        'do seguinte não soa antes da volta', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: rig.notesOf(1).length - 1);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.rewound, isNotEmpty);
      expect(rig.appSoundedAfter(1), isEmpty);
    });

    test(
      'tecla errada no fim do compasso, depois de tocar tudo certo, volta',
      () async {
        rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
        rig.practice.start();
        await rig.playTimed(1);
        // Antes da barra, mas não em cima dela: a tecla errada cair no próprio
        // instante da barra é uma corrida com a nota da barra (não é o caso).
        rig.advanceTo(rig.timeline.measures[1].endMs - 200);
        rig.midi.press(20, atSeconds: rig.engine.now);
        await pumpEventQueue();
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        expect(rig.rewound, isNotEmpty);
        expect(rig.appSoundedAfter(1), isEmpty);
      },
    );

    test('o compasso certo segue sem atraso, cada nota do app sai no instante '
        'dela', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.rewound, isEmpty);
      final app = rig.appNotesOf(2);
      expect(app, isNotEmpty);
      for (final e in app) {
        expect(
          rig.noteOns.any(
            (n) => n.pitch == e.pitch && (n.musical - e.onMs).abs() < 1,
          ),
          isTrue,
          reason: 'nota ${e.pitch} em ${e.onMs} ms',
        );
      }
    });

    test('o salto do caminho (rangeJumps) não se confunde com a volta: a '
        'escada do compasso 3 não mexe no 2, que é pulado', () async {
      rig = _Rig(
        mode: PracticeMode.realtime,
        firstMeasure: 1,
        endMeasure: 4,
        skipMeasure: 2,
      );
      final start3 = rig.timeline.measures[3].startMs.toDouble();
      rig.practice.start();
      await rig.playTimed(1);
      // O compasso 2 é pulado: nada dele é cobrado nem volta.
      await rig.playTimed(3, miss: 0);
      rig.advanceTo(rig.timeline.measures[3].endMs + 400);
      expect(rig.rewound, [(3, start3)]);
      await rig.settle();
      await rig.playWaitMeasure();
      await rig.settle();
      rig.runCountIn();
      await rig.playTimed(3);
      rig.passEnd(3);
      expect(rig.status, isNull);
      await rig.playTimed(4);
      rig.passEnd(4);
      expect(rig.dones, 1);
      expect(rig.practice.stageResult!.rewinds, {3: 2});
      expect(
        rig.practice.report.measures.map((m) => m.index),
        isNot(contains(2)),
      );
    });

    test('a última nota do compasso chega atrasada, depois da barra, num '
        'compasso que já tem erro: volta uma vez, e a nota atrasada não entra '
        'na repetição', () async {
      // O compasso 6 do fixture acaba com uma nota do aluno a 20 ms da barra:
      // a janela dela passa da barra (é o caso).
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 6, endMeasure: 8);
      rig.practice.start();
      final end6 = rig.timeline.measures[6].endMs.toDouble();
      final notes = rig.notesOf(6);
      final last = notes.last;
      final late = end6 + 20;
      expect(late - last.onMs, lessThan(150), reason: 'dentro da janela');
      rig.advanceTo(notes.first.onMs);
      rig.midi.press(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      for (final n in notes.take(notes.length - 1)) {
        rig.advanceTo(n.onMs);
        rig.midi.press(n.pitch, atSeconds: rig.engine.now);
        await pumpEventQueue();
      }
      rig.advanceTo(late);
      rig.midi.press(last.pitch, atSeconds: rig.engine.now);
      await pumpEventQueue();
      expect(rig.rewound, hasLength(1));
      await rig.settle();
      // A repetição só notas, certa de ponta a ponta; depois o andamento.
      await rig.playWaitMeasure();
      await rig.settle();
      rig.runCountIn();
      await rig.playTimed(6);
      rig.passEnd(6);
      expect(rig.status, isNull);
      await rig.playTimed(7);
      rig.passEnd(7);
      expect(rig.dones, 1);
      expect(rig.rewound, hasLength(2));
      expect(rig.practice.stageResult!.rewinds, {6: 2});
    });
  });

  group('volta na hora, modo espera', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test('compasso certo não volta', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playWaitMeasure();
      await rig.playWaitMeasure();
      expect(rig.dones, 1);
      expect(rig.rewound, isEmpty);
      expect(rig.practice.stageResult!.rewinds, isEmpty);
      expect(rig.practice.stageResult!.percent, 100);
    });

    test('tecla errada: o compasso acaba, aviso, e repete só notas; erro na '
        'repetição repete de novo; certo, segue', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      final first = rig.practice.currentStep.value!;
      await rig.playWaitMeasure(wrongAt: 0);
      expect(rig.rewound, [(1, start1)]);
      expect(rig.status!.notice, RepeatNotice.missed);
      // A repetição começa no primeiro passo do compasso, depois do aviso.
      await rig.settle();
      expect(rig.practice.currentStep.value!.index, first.index);
      await rig.playWaitMeasure(wrongAt: 0);
      await rig.settle();
      expect(rig.practice.rewinds, {1: 2});
      await rig.playWaitMeasure();
      expect(rig.practice.rewinds, {1: 2});
      expect(rig.measureOfStep(), 2);
      await rig.playWaitMeasure();
      expect(rig.dones, 1);
      final result = rig.practice.stageResult!;
      expect(result.rewinds, {1: 2});
      expect(result.badMeasures, {1});
      // A tentativa certa conta de primeira: só as duas erradas não.
      expect(result.total - result.hits, 2);
    });

    test('o último compasso repete em vez de acabar', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playWaitMeasure();
      await rig.playWaitMeasure(wrongAt: 0);
      expect(rig.dones, 0);
      await rig.settle();
      expect(rig.practice.rewinds, {2: 1});
      expect(rig.measureOfStep(), 2);
      await rig.playWaitMeasure();
      expect(rig.dones, 1);
    });

    test('modo espera: tecla errada no compasso; nada do seguinte soa antes '
        'da volta', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playWaitMeasure(wrongAt: 0);
      expect(rig.rewound, isNotEmpty);
      expect(rig.appSoundedAfter(1), isEmpty);
    });
  });

  group('o log da volta', () {
    tearDown(DiagLog.reset);

    test(
      'uma linha [volta] por degrau, com compasso, degrau e tentativa',
      () async {
        final store = MemoryDiagStorage();
        await DiagLog.init(storage: store, installHandlers: false);
        final rig = _Rig(
          mode: PracticeMode.realtime,
          firstMeasure: 1,
          endMeasure: 3,
          repeatSpeeds: const [0.5],
        );
        addTearDown(rig.dispose);
        rig.practice.start();
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        await rig.settle();
        await rig.playWaitMeasure();
        await rig.settle();
        rig.runCountIn();
        await rig.playTimed(1);
        rig.passEnd(1);
        await rig.playTimed(2);
        rig.passEnd(2);
        final lines = store
            .read('app')
            .split('\n')
            .where((l) => l.contains('[volta]'))
            .toList();
        expect(lines.every((l) => l.contains('compasso=1')), isTrue);
        expect(lines.any((l) => l.contains('escada de 3 degraus')), isTrue);
        expect(
          lines.where((l) => l.contains('só notas tentativa=1')),
          hasLength(1),
        );
        expect(lines.where((l) => l.contains('50%')), isNotEmpty);
        expect(lines.where((l) => l.contains('contagem=true')), isNotEmpty);
      },
    );
  });
}

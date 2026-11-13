// LP24.2 — A volta na hora no `PracticeController`: o compasso que acaba com
// erro volta ao começo dele (sem contagem) até sair certo, nos dois modos.
// Mesmo arranjo de test/practice_controller_test.dart: agendador de verdade
// sobre um motor falso, o relógio andado à mão.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
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
class _Rig {
  _Rig({
    required this.mode,
    required this.firstMeasure,
    required this.endMeasure,
    this.skipMeasure,
  }) {
    final doc = _loadDoc();
    track = PerformanceTrack.fromDocument(doc);
    timeline = ScoreTimeline(doc);
    scheduler = ScoreAudioScheduler(
      engine: engine,
      track: track,
      autoTick: false,
    );
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
  final FakeSoundEngine engine = FakeSoundEngine();
  final FakeMidiInput midi = FakeMidiInput();
  late final PerformanceTrack track;
  late final ScoreTimeline timeline;
  late final ScoreAudioScheduler scheduler;
  late final ScoreController scoreController;
  late final PracticeController practice;
  int dones = 0;
  final List<(int, double)> rewound = [];

  /// O instante do motor (segundos) de cada volta, na ordem de [rewound].
  final List<double> rewoundAt = [];

  /// As notas do app agendadas ao motor (ataques), com o instante e o tempo
  /// musical de cada uma.
  final List<({double at, int pitch, double musical})> noteOns = [];

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

  void advanceTo(double ms) {
    // Para na volta: depois dela a posição recua, e o alvo pode nunca chegar.
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

  group('volta na hora, tempo real', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test('compasso certo não volta', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.rewound, isEmpty);
      expect(rig.practice.stageResult!.rewinds, isEmpty);
      expect(rig.practice.report.wrong + rig.practice.report.missed, 0);
    });

    test('compasso com nota perdida volta ao começo dele, sem contagem; a '
        'conta e os erros de todas as tentativas vêm no resultado', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      expect(rig.notesOf(1), isNotEmpty);
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.rewound, [(1, start1)]);
      expect(rig.practice.rewinds, {1: 1});
      // O agendador voltou ao começo do compasso, sem contagem.
      expect(rig.scheduler.positionMs, closeTo(start1, 30));
      expect(rig.scheduler.isCountingIn, isFalse);
      await rig.playTimed(1);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.rewound, hasLength(1));
      final result = rig.practice.stageResult!;
      expect(result.rewinds, {1: 1});
      expect(result.badMeasures, contains(1));
      final report = rig.practice.report;
      // O erro da tentativa que voltou fica: errors e measureErrors.
      expect(report.wrong + report.missed, greaterThanOrEqualTo(1));
      final m1 = report.measures.firstWhere((m) => m.index == 1);
      expect(m1.errors, greaterThanOrEqualTo(1));
      // O compasso 2 não tem erro (o que caiu nele na folga saiu).
      expect(
        report.measures.where((m) => m.index == 2 && m.errors > 0),
        isEmpty,
      );
    });

    test('erro na volta volta de novo; tecla errada também volta', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.practice.rewinds, {1: 1});
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.practice.rewinds, {1: 2});
      // Uma tecla errada depois de as certas todas tocadas também volta, na
      // hora: o compasso seguinte pode já estar agendado, então não espera o
      // fim dele.
      await rig.playTimed(1);
      rig.midi.press(20, atSeconds: rig.engine.now);
      await pumpEventQueue();
      expect(rig.practice.rewinds, {1: 3});
      await rig.playTimed(1);
      await rig.playTimed(2);
      rig.passEnd(2);
      expect(rig.dones, 1);
      expect(rig.practice.stageResult!.rewinds, {1: 3});
    });

    test(
      'o último compasso do intervalo também volta antes de acabar',
      () async {
        rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
        rig.practice.start();
        await rig.playTimed(1);
        await rig.playTimed(2, miss: 0);
        rig.advanceTo(rig.timeline.measures[2].endMs + 400);
        expect(rig.dones, 0);
        expect(rig.practice.rewinds, {2: 1});
        await rig.playTimed(2);
        rig.passEnd(2);
        expect(rig.dones, 1);
        expect(rig.practice.stageResult!.rewinds, {2: 1});
      },
    );

    test(
      'o salto do caminho (rangeJumps) não se confunde com a volta',
      () async {
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
        await rig.playTimed(3);
        rig.passEnd(3);
        expect(rig.dones, 1);
        expect(rig.practice.stageResult!.rewinds, {3: 1});
        expect(
          rig.practice.report.measures.map((m) => m.index),
          isNot(contains(2)),
        );
      },
    );
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

    test('tecla errada: o compasso acaba e volta; erro na volta volta de '
        'novo; certo, segue', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      final start1 = rig.timeline.measures[1].startMs.toDouble();
      rig.practice.start();
      final first = rig.practice.currentStep.value!;
      await rig.playWaitMeasure(wrongAt: 0);
      expect(rig.rewound, [(1, start1)]);
      // A música não avançou: o passo pendente é de novo o primeiro.
      expect(rig.practice.currentStep.value!.index, first.index);
      await rig.playWaitMeasure(wrongAt: 0);
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

    test('o último compasso volta em vez de acabar', () async {
      rig = _Rig(mode: PracticeMode.wait, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playWaitMeasure();
      await rig.playWaitMeasure(wrongAt: 0);
      expect(rig.dones, 0);
      expect(rig.practice.rewinds, {2: 1});
      expect(rig.measureOfStep(), 2);
      await rig.playWaitMeasure();
      expect(rig.dones, 1);
    });
  });

  group('o app não toca o compasso seguinte depois de um erro', () {
    late _Rig rig;
    tearDown(() => rig.dispose());

    test('tempo real: nota perdida no começo do compasso', () async {
      rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
      rig.practice.start();
      await rig.playTimed(1, miss: 0);
      rig.advanceTo(rig.timeline.measures[1].endMs + 400);
      expect(rig.rewound, isNotEmpty);
      expect(rig.appSoundedAfter(1), isEmpty);
    });

    test(
      'tempo real: a última nota perdida, que só fecha depois da barra',
      () async {
        rig = _Rig(mode: PracticeMode.realtime, firstMeasure: 1, endMeasure: 3);
        rig.practice.start();
        await rig.playTimed(1, miss: rig.notesOf(1).length - 1);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        expect(rig.rewound, isNotEmpty);
        expect(rig.appSoundedAfter(1), isEmpty);
      },
    );

    test('tempo real: tecla errada no fim do compasso, depois de tocar tudo '
        'certo', () async {
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
    });

    test('tempo real: o compasso certo segue sem atraso, cada nota do app '
        'sai no instante dela', () async {
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

    test('tempo real: a última nota do compasso chega atrasada, depois da '
        'barra, num compasso que já tem erro: volta uma vez, e a nota atrasada '
        'não entra na tentativa seguinte', () async {
      // O compasso 6 do fixture acaba com uma nota do aluno a 0,1 ms da barra:
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
      // A tentativa seguinte, certa de ponta a ponta: nenhuma volta a mais.
      await rig.playTimed(6);
      await rig.playTimed(7);
      rig.passEnd(7);
      expect(rig.dones, 1);
      expect(rig.rewound, hasLength(1));
      expect(rig.practice.stageResult!.rewinds, {6: 1});
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
      'uma linha [volta] por volta, com compasso, tentativa e modo',
      () async {
        final store = MemoryDiagStorage();
        await DiagLog.init(storage: store, installHandlers: false);
        final rig = _Rig(
          mode: PracticeMode.realtime,
          firstMeasure: 1,
          endMeasure: 3,
        );
        addTearDown(rig.dispose);
        rig.practice.start();
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        await rig.playTimed(1, miss: 0);
        rig.advanceTo(rig.timeline.measures[1].endMs + 400);
        await rig.playTimed(1);
        await rig.playTimed(2);
        rig.passEnd(2);
        final lines = store
            .read('app')
            .split('\n')
            .where((l) => l.contains('[volta]'))
            .toList();
        expect(lines, hasLength(2));
        expect(lines[0], contains('compasso=1 tentativa=2 modo=realtime'));
        expect(lines[1], contains('compasso=1 tentativa=3 modo=realtime'));
      },
    );
  });
}

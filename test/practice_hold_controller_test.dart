// ND02 (docs/plano/ND00 e ND02): o `PracticeController(holdNotes: true)`, o modo
// espera que segura a nota. Mesmo arranjo de test/practice_controller_test.dart:
// agendador de verdade sobre o motor falso e o MIDI falso, com o relógio andado
// à mão. A trilha é pequena e feita aqui (sem partitura: a tela é a do
// erik-satie, só para pintar).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_comum/practice/hand.dart';
import 'package:zywny_comum/practice/practice_controller.dart';
import 'package:zywny_comum/practice/practice_session.dart';

import 'support/practice_fakes.dart';

SoundEvent _note(
  String id,
  int pitch,
  double onMs,
  double offMs, {
  int staff = 1,
}) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: offMs,
  staff: staff,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
);

/// Semínima do aluno de 0 a 500 (dó4), semínima de 500 a 1000 (ré4) e, na
/// pauta do app, uma nota longa de 0 a 1000 (dó3).
PerformanceTrack _track() => PerformanceTrack.fromEvents([
  _note('a', 60, 0, 500),
  _note('b', 62, 500, 1000),
  _note('app', 48, 0, 1000, staff: 2),
]);

VsbDocument _loadDoc() => VsbDocument.fromBytes(
  Uint8List.fromList(File('test/fixtures/erik-satie.vsb').readAsBytesSync()),
);

/// Um controlador montado sobre [track], com o agendador e o MIDI falsos.
class _Rig {
  _Rig({
    required this.holdNotes,
    this.range,
    this.rewindOnError = false,
    PerformanceTrack? track,
  }) : track = track ?? _track() {
    scheduler = ScoreAudioScheduler(
      engine: engine,
      track: this.track,
      autoTick: false,
    );
    practice = PracticeController(
      midiInput: midi,
      track: this.track,
      scheduler: scheduler,
      controller: ScoreController(document: _loadDoc()),
      hand: Hand.direita,
      mode: PracticeMode.wait,
      holdNotes: holdNotes,
      range: range,
      onRangeDone: () => rangeDone++,
      rewindOnError: rewindOnError,
      measureIndexAt: rewindOnError ? (ms) => ms < 500 ? 0 : 1 : null,
      measureSpanOf: rewindOnError
          ? (i) =>
                i == 0 ? (startMs: 0, endMs: 500) : (startMs: 500, endMs: 1000)
          : null,
    );
  }

  final bool holdNotes;
  final ({double startMs, double endMs})? range;
  final bool rewindOnError;
  final PerformanceTrack track;
  final FakeSoundEngine engine = FakeSoundEngine();
  final FakeMidiInput midi = FakeMidiInput();
  late final ScoreAudioScheduler scheduler;
  late final PracticeController practice;
  int rangeDone = 0;

  Future<void> press(int pitch) async {
    midi.press(pitch, atSeconds: engine.now);
    await pumpEventQueue();
  }

  Future<void> release(int pitch) async {
    midi.release(pitch, atSeconds: engine.now);
    await pumpEventQueue();
  }

  /// Anda o relógio (e o agendador) até [targetMs] da música. O freio segura a
  /// posição, então o laço para exatamente no freio.
  void advanceTo(double targetMs) {
    var guard = 0;
    while (scheduler.positionMs < targetMs) {
      engine.now += 0.005;
      scheduler.pump();
      if (++guard > 200000) {
        throw StateError('advanceTo não chegou a $targetMs ms');
      }
    }
  }

  void dispose() {
    practice.dispose();
    midi.dispose();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PracticeController com notas com duração (holdNotes)', () {
    test('sem holdNotes, o aperto fecha o passo na hora (guarda)', () async {
      final rig = _Rig(holdNotes: false)..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);

      expect(rig.practice.report.correct, 1);
      expect(rig.practice.currentStep.value!.index, 1);
      expect(rig.practice.currentStep.value!.holdEndMs, isNull);
      expect(rig.practice.earlyReleases, 0);
    });

    test('segurando, a cápsula enche em 60% da nota e o passo fecha no tique; '
        'a música do app toca enquanto o aluno segura', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);
      // A cápsula da semínima de 0 a 500 vai de 0 a 300 (60%); o freio fica no
      // fim da nota (500), não no fim da cápsula.
      final held = rig.practice.currentStep.value!;
      expect(held.holdEndMs, closeTo(300, 1e-6));
      expect(held.holdParkMs, closeTo(500, 1e-6));
      rig.advanceTo(300);
      expect(rig.scheduler.positionMs, closeTo(300, 1e-6));
      // Cápsula cheia, mas sem tique: o passo ainda não fechou, e a música não
      // parou nela (seguiu pelo relógio livre).
      expect(rig.practice.currentStep.value!.index, 0);
      rig.engine.now += 0.02;
      rig.scheduler.pump();
      expect(rig.scheduler.positionMs, closeTo(320, 1e-6));

      // O relógio da cápsula chega ao fim: o passo fecha e o freio vai para o
      // `onMs` do seguinte (500), sem a música ter perdido tempo.
      rig.practice.debugTickHold();
      expect(rig.practice.report.correct, 1);
      expect(rig.practice.currentStep.value!.index, 1);
      expect(rig.practice.currentStep.value!.holdEndMs, isNull);
      expect(rig.scheduler.positionMs, closeTo(320, 1e-6));
      rig.advanceTo(500);
      expect(rig.scheduler.positionMs, 500);

      // A parte do app (a nota longa de dó3) soou enquanto o aluno segurava.
      expect(
        rig.engine.scheduled.any(
          (e) => e.status & 0xF0 == 0x90 && e.d1 == 48 && e.d2 > 0,
        ),
        isTrue,
      );
    });

    test('o tique atrasado não atrasa a música: o passo seguinte chega no '
        'relógio livre, mesmo que o passo feche bem depois da cápsula cheia '
        '(sem a deriva de ~13 ms por nota do freio no fim da cápsula)', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);
      // O tique de 70 ms: a cápsula enche em 300 e o passo só fecha em 350.
      var ms = 0;
      while (rig.practice.currentStep.value!.index == 0) {
        rig.engine.now += 0.001;
        rig.scheduler.pump();
        if (++ms % 70 == 0) rig.practice.debugTickHold();
        expect(ms, lessThan(1000));
      }
      expect(ms, 350);

      // A semínima seguinte começa em 500 do relógio livre: 0,5 s depois do
      // aperto, e não 0,55 s (os 50 ms que a música ficaria parada em 300).
      rig.advanceTo(500);
      expect(rig.engine.now, closeTo(0.5, 0.006));
    });

    test('soltar cedo não é erro: a música volta ao começo da nota, a nota '
        'volta a faltar, e apertar de novo arma a cápsula', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);
      final releases = <HoldRelease>[];
      rig.practice.holdReleases.listen(releases.add);

      await rig.press(60);
      rig.advanceTo(200);
      await rig.release(60);

      expect(rig.practice.earlyReleases, 1);
      expect(releases.single.pitch, 60);
      expect(releases.single.fraction, closeTo(2 / 3, 1e-9));
      expect(rig.scheduler.positionMs, 0);
      final step = rig.practice.currentStep.value!;
      expect(step.index, 0);
      expect(step.remaining, contains(60));
      expect(step.holdEndMs, isNull);
      // Nada conta como erro nem como acerto.
      expect(rig.practice.report.correct, 0);
      expect(rig.practice.report.wrong, 0);
      expect(rig.practice.wrongCount.value, 0);

      await rig.press(60);
      expect(rig.practice.currentStep.value!.holdEndMs, 300);
    });

    test('a soltura antes do primeiro tique sai com o tempo certo (o '
        'controlador anda o relógio antes de cada tecla)', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);
      final releases = <HoldRelease>[];
      rig.practice.holdReleases.listen(releases.add);

      await rig.press(60);
      // Nenhum tique do relógio da cápsula: só o tempo que passou.
      rig.engine.now += 0.2;
      await rig.release(60);

      expect(releases.single.atMs, 200);
      expect(releases.single.fraction, closeTo(2 / 3, 1e-9));
    });

    test('tecla errada no meio da cápsula (250 ms depois do aperto) '
        'não fecha o passo; soltar a errada fecha depois do fim', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);
      rig.advanceTo(250);
      await rig.press(61);
      expect(rig.practice.report.wrong, 1);
      expect(rig.practice.report.correct, 0);
      expect(rig.practice.currentStep.value!.index, 0);
      expect(rig.practice.currentStep.value!.holdEndMs, 300);

      rig.advanceTo(300);
      rig.practice.debugTickHold();
      // A errada ainda está presa: a cápsula cheia não basta.
      expect(rig.practice.currentStep.value!.index, 0);
      expect(rig.practice.report.correct, 0);

      await rig.release(61);
      expect(rig.practice.report.correct, 1);
      expect(rig.practice.report.wrong, 1);
      expect(rig.practice.currentStep.value!.index, 1);
    });

    test('tecla errada no meio da cápsula e soltura certa antes do fim: '
        'é soltura cedo, a errada segue sendo só o veredito', () async {
      final rig = _Rig(holdNotes: true)..practice.start();
      addTearDown(rig.dispose);
      final releases = <HoldRelease>[];
      rig.practice.holdReleases.listen(releases.add);

      await rig.press(60);
      rig.advanceTo(250);
      await rig.press(61);
      rig.advanceTo(280);
      await rig.release(60);

      expect(rig.practice.earlyReleases, 1);
      expect(releases.single.fraction, closeTo(280 / 300, 1e-9));
      final step = rig.practice.currentStep.value!;
      expect(step.index, 0);
      expect(step.remaining, contains(60));
      expect(rig.practice.report.correct, 0);
      expect(rig.practice.report.wrong, 1);
    });

    test('com intervalo e volta na hora, a rodada inteira segurada sai limpa '
        'e sem volta', () async {
      final rig = _Rig(
        holdNotes: true,
        range: (startMs: 0, endMs: 1000),
        rewindOnError: true,
      )..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);
      rig.advanceTo(400);
      rig.practice.debugTickHold();
      rig.advanceTo(500);
      await rig.press(62);
      rig.advanceTo(900);
      rig.practice.debugTickHold();

      expect(rig.rangeDone, 1);
      final result = rig.practice.stageResult!;
      expect(result.total, 2);
      expect(result.hits, 2);
      expect(result.badMeasures, isEmpty);
      expect(rig.practice.rewinds, isEmpty);
      expect(rig.practice.earlyReleases, 0);
    });

    test('a nota que dura além do fim do intervalo fecha no fim dele (o freio '
        'não passa do intervalo)', () async {
      final rig = _Rig(
        holdNotes: true,
        range: (startMs: 0, endMs: 500),
        track: PerformanceTrack.fromEvents([_note('a', 60, 0, 1000)]),
      )..practice.start();
      addTearDown(rig.dispose);

      await rig.press(60);
      // A cápsula iria a 600, mas o freio para em 499 (fim do intervalo).
      rig.advanceTo(499);
      expect(rig.scheduler.positionMs, 499);
      rig.practice.debugTickHold();

      expect(rig.rangeDone, 1);
      expect(rig.practice.stageResult!.hits, 1);
    });
  });
}

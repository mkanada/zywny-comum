// J08 — Saltos no caminho (D-SALTO via a): o trecho cruza a casa direto na
// casa 2 — o agendador pula o vão e as sessões nem o avaliam.
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/metronome.dart';
import 'package:zywny_audio/score_audio_scheduler.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_midi/midi_input_service.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_controller.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/trail/trail_segments.dart';
import 'package:zywny/trail/trail_stage.dart';

class _Occ {
  const _Occ(this.id, this.pass, this.t, this.q);
  final String id;
  final int pass;
  final double t;
  final double q;
}

VsbDocument _fakeTrailDoc({
  required List<String> docOrder,
  required List<_Occ> occurrences,
  required double finalT,
  required double finalQ,
}) {
  ScenePage page() {
    final byId = <String, SceneNode>{};
    final elements = <IndexEntry>[];
    final children = <SceneChild>[];
    var path = 0;
    for (final id in docOrder) {
      final node = SceneNode(
        id: id,
        className: 'measure',
        hidden: false,
        bbox: const Rect.fromLTWH(0, 0, 100, 100),
        children: const [],
      );
      children.add(node);
      byId[id] = node;
      elements.add(
        IndexEntry(
          id: id,
          className: 'measure',
          nodePath: ++path,
          bbox: node.bbox!,
        ),
      );
    }
    return ScenePage(
      index: 0,
      width: 1000,
      height: 1400,
      contentHeight: 1400,
      viewBoxFactor: 1,
      viewBox: const Rect.fromLTWH(0, 0, 1000, 1400),
      baseWidth: 1000,
      baseHeight: 1400,
      userScaleX: 1,
      userScaleY: 1,
      widthPx: 1000,
      heightPx: 1400,
      fit: const PageFit(scale: 1, tx: 0, ty: 0),
      origin: Offset.zero,
      root: SceneNode(className: 'page', hidden: false, children: children),
      elements: elements,
      byId: byId,
    );
  }

  return VsbDocument(
    manifest: const VsbManifest(
      format: 'vsb',
      version: 1,
      generator: 'test',
      pageCount: 1,
      files: VsbManifestFiles(scene: 'scene.json', glyphs: 'glyphs.json'),
    ),
    glyphs: const {},
    pages: [page()],
    timemap: [
      for (final o in occurrences)
        TimemapEntry(
          qstamp: o.q,
          tstamp: o.t,
          on: const [],
          off: const [],
          restsOn: const [],
          restsOff: const [],
          measureOn: o.pass == 1 ? o.id : '${o.id}-rend${o.pass}',
        ),
      TimemapEntry(
        qstamp: finalQ,
        tstamp: finalT,
        on: const [],
        off: const [],
        restsOn: const [],
        restsOff: const [],
      ),
    ],
  );
}

const _houseOccurrences = [
  _Occ('A', 1, 0, 0),
  _Occ('B', 1, 1000, 4),
  _Occ('C', 1, 2000, 8),
  _Occ('A', 2, 3000, 12),
  _Occ('B', 2, 4000, 16),
  _Occ('D', 1, 5000, 20),
  _Occ('E', 1, 6000, 24),
];

VsbDocument _houseDoc() => _fakeTrailDoc(
  docOrder: const ['A', 'B', 'C', 'D', 'E'],
  occurrences: _houseOccurrences,
  finalT: 7000,
  finalQ: 28,
);

TrailPath _housePath() => TrailPath.fromTimeline(ScoreTimeline(_houseDoc()));

class _Engine implements SoundEngine {
  double now = 0;
  final List<ScheduledMidi> scheduled = [];
  int allNotesOffCalls = 0;

  @override
  double get nowSeconds => now;
  @override
  double get earliestScheduleSeconds => now + 0.02;
  @override
  double get outputLatencySeconds => 0.02;
  @override
  Future<void> start() async {}
  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}
  @override
  void send(List<int> midi) {}
  @override
  void schedule(List<ScheduledMidi> events) => scheduled.addAll(events);
  @override
  void clearScheduled() {}
  @override
  void allNotesOff() {
    allNotesOffCalls++;
  }

  @override
  Future<void> dispose() async {}
}

class _Midi implements MidiInputService {
  final StreamController<PlayedNote> _notes =
      StreamController<PlayedNote>.broadcast();
  final ValueNotifier<Set<int>> _held = ValueNotifier(const {});

  @override
  Stream<PlayedNote> get notes => _notes.stream;
  @override
  Stream<int> get sustain => const Stream.empty();
  @override
  ValueListenable<Set<int>> get held => _held;

  void press(int pitch, {double atSeconds = 0}) {
    _notes.add(
      PlayedNote(
        pitch: pitch,
        velocity: 80,
        channel: 0,
        on: true,
        atSeconds: atSeconds,
      ),
    );
  }

  void release(int pitch, {double atSeconds = 0}) {
    _notes.add(
      PlayedNote(
        pitch: pitch,
        velocity: 0,
        channel: 0,
        on: false,
        atSeconds: atSeconds,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_notes.close());
    _held.dispose();
  }
}

SoundEvent _ev(int staff, int pitch, double onMs) => SoundEvent(
  id: 'e$staff-$pitch@${onMs.toInt()}',
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + 400,
  staff: staff,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
);

/// Pista sintética com casas: B1 (1000), vão C/A2/B2 (2000–5000), D (5000).
/// Cada onset um pitch único (casa soa se for agendada).
PerformanceTrack _houseTrack() => PerformanceTrack.fromEvents([
  _ev(1, 71, 1000),
  _ev(2, 41, 1100),
  _ev(1, 72, 2000),
  _ev(1, 73, 3000),
  _ev(1, 74, 4000),
  _ev(2, 42, 4100),
  _ev(1, 75, 5000),
]);

const _houseInterval = (startMs: 1000.0, endMs: 6000.0);
const _houseGaps = [(startMs: 2000.0, endMs: 5000.0)];

void _advanceUntil(
  _Engine engine,
  ScoreAudioScheduler scheduler,
  double targetMs,
) {
  var guard = 0;
  while (scheduler.positionMs < targetMs) {
    engine.now += 0.025;
    scheduler.pump();
    guard++;
    if (guard > 200000) {
      throw StateError('_advanceUntil não convergiu para $targetMs ms');
    }
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('caminho e corte com salto (critério 1)', () {
    test('casas: A B D E com salto antes de D; trecho cruza o vão', () {
      final path = _housePath();
      expect(path.measureCount, 4);
      expect(path.isContiguous, isFalse);
      expect(path.jumps, [2]);
      expect(
        [for (final m in path.logical) m.measures.single.occurrence],
        [0, 1, 5, 6],
      );
      // O corte atravessa o salto (J08): o trecho cobre B1..D.
      final segments = cutSegments(path, 3);
      expect(segments, hasLength(2));
      expect(segments.first.startMs, 0);
      expect(segments.first.endMs, 6000);
      // O vão dentro do trecho: do fim de B1 ao início de D.
      final track = _houseTrack();
      final plan = TrailPlan.build(path, track, n: 3);
      final junto = plan.stages.firstWhere((s) => s.id == 't0.junto.100');
      final gaps = trailStageGaps(path, junto);
      expect(gaps, hasLength(1));
      expect(gaps.single.startMs, 2000);
      expect(gaps.single.endMs, 5000);
    });
  });

  group('número do compasso no caminho (U07)', () {
    test('ocorrência → número do caminho, igual ao da gaveta', () {
      final path = _housePath();
      // Ocorrências do caminho: [0, 1, 5, 6] (A, B, D, E; a casa 1 fica fora).
      expect(path.numberOf(0), 1);
      expect(path.numberOf(5), 3);
      expect(path.numberOf(6), 4);
      expect(path.numberOf(2), isNull); // casa descartada: fora do caminho
      expect(path.numberOf(5), path.logical[2].number);
      expect(path.startMsOfNumber(3), path.logical[2].startMs);
      expect(path.startMsOfNumber(99), isNull);
    });
  });

  group('compassos marcados na pauta (U02)', () {
    test('trecho 1 e 2 com casas; fase final vazia', () {
      final timeline = ScoreTimeline(_houseDoc());
      final path = TrailPath.fromTimeline(timeline);
      final plan = TrailPlan.build(
        path,
        _houseTrack(),
        n: 3,
        includeFinal: true,
      );
      List<String> ids(TrailStage s) =>
          trailStageMeasureIds(path, s, timeline.measures);
      final first = plan.stages.firstWhere((s) => s.segment == 0);
      final second = plan.stages.firstWhere((s) => s.segment == 1);
      final last = plan.stages.firstWhere((s) => s.segment == null);
      final all = [
        for (final m in path.logical)
          timeline.measures[m.measures.first.occurrence].id,
      ];
      expect(ids(first), all.sublist(0, 3));
      // Trechos vizinhos compartilham um compasso (J00).
      expect(ids(second), all.sublist(2));
      expect(ids(last), isEmpty);
    });
  });

  group('agendador pula o vão (critérios 1 e 3)', () {
    test('nada do vão é agendado; destino avisado; metrônomo fora do vão', () {
      final track = _houseTrack();
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      addTearDown(scheduler.dispose);
      scheduler.setStaves(const {2});
      scheduler.beats = const [
        Beat(1000, accent: true, measure: 0),
        Beat(3000, accent: true, measure: 1),
        Beat(5000, accent: true, measure: 2),
      ];
      scheduler.metronomeOn = true;
      final jumps = <double>[];
      scheduler.onJump = jumps.add;
      scheduler.setStopAt(6000);
      scheduler.setJumps(const [(startMs: 2000, endMs: 5000)]);
      scheduler.play(1000);
      _advanceUntil(engine, scheduler, 6500);
      engine.now += 1.0;
      scheduler.pump();

      // Mão do app (pauta 2): só a 41 (o 42 está no vão).
      final pitched = <int>[
        for (final m in engine.scheduled)
          if (m.status & 0xF0 == 0x90 && m.status & 0x0F != 0x09) m.d1,
      ];
      expect(pitched, [41]);
      // Um salto, no destino, e posição além do fim.
      expect(scheduler.jumpCount, 1);
      expect(jumps, [5000]);
      expect(scheduler.positionMs, greaterThanOrEqualTo(6000));
      // Metrônomo: os de fora (1000 e 5000); o do vão (3000), não.
      final clicks = <int>[
        for (final m in engine.scheduled)
          if (m.status & 0xF0 == 0x90 && m.status & 0x0F == 0x09) m.d1,
      ];
      expect(clicks, hasLength(2));
      scheduler.pause();
      expect(engine.allNotesOffCalls, greaterThan(0));
    });
  });

  group('passagem única com salto nas três modalidades (critério 1)', () {
    Future<PracticeController> startStage({
      required PerformanceTrack track,
      required PracticeMode mode,
      required _Engine engine,
      required ScoreAudioScheduler scheduler,
      required ScoreController controller,
      required _Midi midi,
      required ScoreTimeline timeline,
      required void Function() onDone,
      required List<double> jumped,
    }) async {
      final practice = PracticeController(
        midiInput: midi,
        track: track,
        scheduler: scheduler,
        controller: controller,
        hand: Hand.direita,
        mode: mode,
        measureIndexAt: timeline.measureIndexAt,
        passOf: (i) => timeline.measures[i].pass,
        range: _houseInterval,
        rangeJumps: _houseGaps,
        onRangeDone: onDone,
        onRangeJump: jumped.add,
      );
      addTearDown(practice.dispose);
      practice.start();
      return practice;
    }

    Future<void> playStep(
      _Midi midi,
      _Engine engine,
      ScoreAudioScheduler scheduler,
      PracticeController practice,
    ) async {
      final step = practice.currentStep.value!;
      _advanceUntil(engine, scheduler, step.onMs);
      for (final e in step.notes) {
        midi.press(e.pitch, atSeconds: engine.now);
      }
      await pumpEventQueue();
      for (final e in step.notes) {
        midi.release(e.pitch, atSeconds: engine.now);
      }
      await pumpEventQueue();
    }

    test('espera cruza a casa: 100% em 2 passos, sem nada do vão', () async {
      final track = _houseTrack();
      final timeline = ScoreTimeline(_houseDoc());
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final controller = ScoreController(document: _houseDoc());
      addTearDown(controller.dispose);
      addTearDown(controller.clearAll);
      final midi = _Midi();
      addTearDown(midi.dispose);
      var dones = 0;
      final jumped = <double>[];
      final practice = await startStage(
        track: track,
        mode: PracticeMode.wait,
        engine: engine,
        scheduler: scheduler,
        controller: controller,
        midi: midi,
        timeline: timeline,
        onDone: () => dones++,
        jumped: jumped,
      );

      var guard = 0;
      while (dones == 0 && guard++ < 100) {
        await playStep(midi, engine, scheduler, practice);
      }
      expect(dones, 1);
      expect(jumped, [5000]);
      final result = practice.stageResult!;
      expect(practice.liveScore.value, (
        hits: result.hits,
        total: result.total,
      ));
      expect(result.percent, 100);
      expect(result.total, 2);
      practice.stop();
    });

    test('espera com tecla errada: passo fora e compasso marcado', () async {
      final track = _houseTrack();
      final timeline = ScoreTimeline(_houseDoc());
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final controller = ScoreController(document: _houseDoc());
      addTearDown(controller.dispose);
      addTearDown(controller.clearAll);
      final midi = _Midi();
      addTearDown(midi.dispose);
      var dones = 0;
      final practice = await startStage(
        track: track,
        mode: PracticeMode.wait,
        engine: engine,
        scheduler: scheduler,
        controller: controller,
        midi: midi,
        timeline: timeline,
        onDone: () => dones++,
        jumped: <double>[],
      );

      final target = practice.currentStep.value!;
      final targetMeasure = timeline.measureIndexAt(target.onMs);
      midi.press(200, atSeconds: engine.now);
      await pumpEventQueue();
      // Enquanto a errada estiver apertada o acorde não fecha.
      midi.release(200, atSeconds: engine.now);
      await pumpEventQueue();
      var guard = 0;
      while (dones == 0 && guard++ < 100) {
        await playStep(midi, engine, scheduler, practice);
      }
      expect(dones, 1);
      final result = practice.stageResult!;
      expect(practice.liveScore.value, (
        hits: result.hits,
        total: result.total,
      ));
      expect(result.total, 2);
      expect(result.percent, lessThan(100));
      expect(result.badMeasures, contains(targetMeasure));
      practice.stop();
    });

    test('tempo real cruza a casa no tempo: 100%, sem missed do vão', () async {
      final track = _houseTrack();
      final timeline = ScoreTimeline(_houseDoc());
      final engine = _Engine();
      final scheduler = ScoreAudioScheduler(
        engine: engine,
        track: track,
        autoTick: false,
      );
      final controller = ScoreController(document: _houseDoc());
      addTearDown(controller.dispose);
      addTearDown(controller.clearAll);
      final midi = _Midi();
      addTearDown(midi.dispose);
      var dones = 0;
      final jumped = <double>[];
      final practice = await startStage(
        track: track,
        mode: PracticeMode.realtime,
        engine: engine,
        scheduler: scheduler,
        controller: controller,
        midi: midi,
        timeline: timeline,
        onDone: () => dones++,
        jumped: jumped,
      );

      for (final (ms, pitch) in [(1000.0, 71), (5000.0, 75)]) {
        _advanceUntil(engine, scheduler, ms);
        midi.press(pitch, atSeconds: engine.now);
        await pumpEventQueue();
      }
      _advanceUntil(engine, scheduler, 7000);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(dones, 1);
      expect(jumped, [5000]);
      final result = practice.stageResult!;
      expect(practice.liveScore.value, (
        hits: result.hits,
        total: result.total,
      ));
      expect(result.percent, 100);
      // Só B1 e D avaliados: nada de C/A2/B2 (vão).
      expect(result.total, 2);
      practice.stop();
    });
  });

  group('fixtures (critério 4 parcial)', () {
    test('hinos com casas voltam à trilha; resto segue no livre', () {
      for (final (name, jumps) in [
        ('erik-satie.vsb', [31]),
        ('maple-leaf-rag.vsb', [15, 31, 63, 79]),
      ]) {
        final bytes = File('test/fixtures/$name').readAsBytesSync();
        final path = TrailPath.fromTimeline(
          ScoreTimeline(VsbDocument.fromBytes(bytes)),
        );
        expect(path.measureCount, greaterThan(0), reason: name);
        expect(path.jumps, jumps, reason: name);
        // O corte atravessa: há trechos (a trilha abre).
        expect(cutSegments(path, 5), isNotEmpty, reason: name);
        // ignore: avoid_print
        print('$name: lógicos=${path.measureCount} saltos=${path.jumps}');
      }
    });
  });
}

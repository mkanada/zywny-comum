// J07 — Fase final e reforço (controlador).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_controller.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/trail/trail_progress.dart';

TrailPath _path(int measures) => TrailPath(
  logical: [
    for (var i = 0; i < measures; i++)
      LogicalMeasure(
        measures: [
          PathMeasure(
            occurrence: i,
            startMs: i * 1000.0,
            endMs: (i + 1) * 1000.0,
          ),
        ],
        startMs: i * 1000.0,
        endMs: (i + 1) * 1000.0,
        number: i + 1,
      ),
  ],
  jumps: const [],
);

TrailPlan _plan() => TrailPlan.build(
  _path(20),
  PerformanceTrack.fromEvents([
    for (var i = 0; i < 20; i++) ...[
      SoundEvent(
        id: 'r$i',
        pitch: 72,
        onMs: i * 1000.0 + 100,
        offMs: i * 1000.0 + 500,
        staff: 1,
        channel: 0,
        program: 0,
        velocity: 80,
        ornament: false,
      ),
      SoundEvent(
        id: 'l$i',
        pitch: 48,
        onMs: i * 1000.0 + 200,
        offMs: i * 1000.0 + 500,
        staff: 2,
        channel: 0,
        program: 0,
        velocity: 80,
        ornament: false,
      ),
    ],
  ]),
  n: 5,
);

StageResult _pct(int hits, int total, [Set<int> bad = const {}]) =>
    StageResult(hits: hits, total: total, badMeasures: bad);

TrailController _controller({TrailProgress? progress}) {
  final plan = _plan();
  return TrailController(
    path: _path(20),
    plan: plan,
    progress: progress ?? TrailProgress(n: 5, total: plan.stages.length),
    store: TrailProgressStore(),
    pieceId: '012',
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// Aprova todos os trechos para a fase final abrir.
  Future<void> passSegments(TrailController c) async {
    while (c.selected != null && c.selected!.segment != null) {
      await c.recordDone(_pct(19, 20));
    }
  }

  test(
    'reprovou final.50 com erros em 7,8 → bloco [6-9] a 50% (critério 1)',
    () async {
      final c = _controller();
      await passSegments(c);
      expect(c.selected?.id, 'final.50');
      await c.recordDone(_pct(17, 20, {7, 8}));
      expect(c.progress.stateOf('final.50'), StageState.pendente);
      expect(c.startReinforcement(_pct(17, 20, {7, 8})), isTrue);
      expect(c.reinforcing, isTrue);
      expect(c.reinforcementSpeed, 0.5);
      expect(
        [
          for (final b in c.blockViews) [b.first, b.last],
        ],
        [
          [6, 9],
        ],
      );
      expect(c.selected?.label, 'Reforço 1/1 · compassos 7–10 · 50%');
      c.recordBlockDone(0, _pct(9, 10));
      expect(c.reinforcing, isFalse);
      expect(c.selected?.id, 'final.50');
    },
  );

  test('dois blocos: pular um e aprovar o outro reabre, sem pular a final '
      '(critério 2)', () async {
    final c = _controller();
    await passSegments(c);
    await c.recordDone(_pct(17, 20, {3, 12}));
    expect(c.startReinforcement(_pct(17, 20, {3, 12})), isTrue);
    expect(c.blockViews, hasLength(2));
    c.skipBlock(0);
    expect(c.reinforcing, isTrue);
    expect(c.progress.stateOf('final.50'), StageState.pendente);
    c.recordBlockDone(1, _pct(9, 10));
    expect(c.reinforcing, isFalse);
    expect(c.progress.stateOf('final.50'), StageState.pendente);
    expect(c.selected?.id, 'final.50');
  });

  test('final.75 aprovada abre a final.100 sem reforço (critério 3)', () async {
    final c = _controller();
    await passSegments(c);
    await c.recordDone(_pct(19, 20));
    expect(c.selected?.id, 'final.75');
    await c.recordDone(_pct(19, 20));
    expect(c.selected?.id, 'final.100');
    expect(c.reinforcing, isFalse);
  });

  test('bloco da música inteira ou vazio: sem reforço (critério 4)', () async {
    final c = _controller();
    await passSegments(c);
    await c.recordDone(_pct(10, 20, {for (var i = 0; i < 20; i++) i}));
    expect(
      c.startReinforcement(_pct(10, 20, {for (var i = 0; i < 20; i++) i})),
      isFalse,
    );
    expect(c.reinforcing, isFalse);
    expect(c.startReinforcement(_pct(10, 20, const {})), isFalse);
  });

  test('recriar no meio do reforço descarta (critério 5)', () async {
    final c = _controller();
    await passSegments(c);
    await c.recordDone(_pct(17, 20, {7, 8}));
    expect(c.startReinforcement(_pct(17, 20, {7, 8})), isTrue);
    final c2 = _controller(progress: c.progress);
    expect(c2.reinforcing, isFalse);
    expect(c2.selected?.id, 'final.50');
  });

  test('final.100 aprovada conclui (critério 6)', () async {
    final c = _controller();
    await passSegments(c);
    expect(c.progress.finalApproved, isFalse);
    await c.recordDone(_pct(19, 20));
    await c.recordDone(_pct(19, 20));
    await c.recordDone(_pct(19, 20));
    expect(c.progress.finalApproved, isTrue);
    expect(c.progress.current(c.plan), isNull);
  });
}

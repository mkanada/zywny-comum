// J05 — TrailController: seleção, registro, pulo e modos.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/music/performance_track.dart';
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

SoundEvent _ev(int staff, double onMs) => SoundEvent(
  id: 'e$staff@${onMs.toInt()}',
  pitch: staff == 1 ? 72 : 48,
  onMs: onMs,
  offMs: onMs + 500,
  staff: staff,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
);

TrailPlan _plan() => TrailPlan.build(
  _path(6),
  PerformanceTrack.fromEvents([
    _ev(1, 100),
    _ev(2, 200),
    _ev(1, 4100),
    _ev(2, 4200),
  ]),
  n: 5,
  includeFinal: false,
);

StageResult _pct(int hits, int total) =>
    StageResult(hits: hits, total: total, badMeasures: const {});

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  TrailController controller({int? hymn = 12, TrailProgress? progress}) {
    final plan = _plan();
    return TrailController(
      path: _path(6),
      plan: plan,
      progress: progress ?? TrailProgress(n: 5, total: plan.stages.length),
      store: TrailProgressStore(),
      hymnNumber: hymn,
    );
  }

  test('selecionada é a atual; trancada não seleciona', () {
    final c = controller();
    expect(c.selected?.id, 't0.notasD');
    c.select('t0.ritmoD.50');
    expect(c.selected?.id, 't0.notasD');
    c.select('t0.notasD');
    expect(c.selected?.id, 't0.notasD');
  });

  test('recordDone aprova, guarda e expõe para o resumo', () async {
    final c = controller();
    await c.recordDone(_pct(9, 10));
    expect(c.progress.stateOf('t0.notasD'), StageState.aprovada);
    expect(c.lastResult?.percent, 90);
    expect(c.lastStage?.id, 't0.notasD');
    // Sem seleção explícita, a faixa segue a atual (a próxima).
    expect(c.selected?.id, 't0.notasE');
    c.next();
    expect(c.selected?.id, 't0.notasE');
    final stored = c.store[12];
    expect(stored.stateOf('t0.notasD'), StageState.aprovada);
  });

  test('repetir pelo resumo: a aprovada continua selecionada, não a '
      'seguinte', () async {
    final c = controller();
    final done = c.selected!;
    expect(done.id, 't0.notasD');
    await c.recordDone(_pct(10, 10));
    // Aprovada: a atual já andou para a seguinte.
    expect(c.selected?.id, 't0.notasE');
    c.repeat(done);
    expect(c.selected?.id, 't0.notasD');
    c.next();
    expect(c.selected?.id, 't0.notasE');
  });

  test('com etapa rodando a seleção não muda', () async {
    final c = controller();
    await c.recordDone(_pct(10, 10));
    c.setRunning(true);
    c.select('t0.notasD');
    expect(c.selected?.id, 't0.notasE');
    c.setRunning(false);
    c.select('t0.notasD');
    expect(c.selected?.id, 't0.notasD');
  });

  test('skipSelected só pula pendente', () async {
    final c = controller();
    await c.skipSelected();
    expect(c.progress.stateOf('t0.notasD'), StageState.pulada);
    expect(c.selected?.id, 't0.notasE');
    c.next();
    expect(c.selected?.id, 't0.notasE');
    await c.recordDone(_pct(19, 20));
    await c.skipSelected();
    expect(c.progress.stateOf('t0.notasE'), StageState.aprovada);
  });

  test('corte diferente começa vazio', () {
    final c = controller(
      progress: const TrailProgress(
        n: 4,
        total: 99,
        records: {
          't0.notasD': StageRecord(state: StageState.aprovada, best: 95),
        },
      ),
    );
    expect(c.progress.n, 5);
    expect(c.progress.doneCount(c.plan), 0);
    expect(c.selected?.id, 't0.notasD');
  });

  test('sem número de hino não persiste', () async {
    final c = controller(hymn: null);
    await c.recordDone(_pct(9, 10));
    expect(c.progress.stateOf('t0.notasD'), StageState.aprovada);
    expect(await SharedPreferencesAsync().getString('trail_12'), isNull);
  });

  test('freeMode e running avisam', () {
    final c = controller();
    var calls = 0;
    c.addListener(() => calls++);
    c.setFreeMode(true);
    c.setRunning(true);
    c.setRunning(true);
    expect(calls, 2);
  });
}

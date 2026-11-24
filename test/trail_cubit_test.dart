// J05 — TrailCubit: seleção, registro, pulo e modos.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/trail/stage_result.dart';
import 'package:zywny_comum/trail/trail_cubit.dart';
import 'package:zywny_comum/trail/trail_path.dart';
import 'package:zywny_comum/trail/trail_plan.dart';
import 'package:zywny_comum/trail/trail_progress.dart';
import 'package:zywny_comum/trail/trail_progress_cubit.dart';

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
  options: TrailPlanOptions(includeFinal: false),
);

StageResult _pct(int hits, int total) =>
    StageResult(hits: hits, total: total, badMeasures: const {});

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  TrailCubit controller({String? piece = '012', TrailProgress? progress}) {
    final plan = _plan();
    return TrailCubit(
      path: _path(6),
      plan: plan,
      progress: progress ?? TrailProgress(n: 5, total: plan.stages.length),
      store: TrailProgressCubit(),
      pieceId: piece,
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
    final stored = c.store['012'];
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
    final c = controller(piece: null);
    await c.recordDone(_pct(9, 10));
    expect(c.progress.stateOf('t0.notasD'), StageState.aprovada);
    expect(await SharedPreferencesAsync().getString('trail_12'), isNull);
  });

  blocTest<TrailCubit, TrailState>(
    'freeMode e running avisam, e só quando mudam',
    build: () => controller(),
    act: (c) {
      c.setFreeMode(true);
      c.setRunning(true);
      c.setRunning(true);
    },
    expect: () => [
      isA<TrailState>().having((s) => s.freeMode, 'freeMode', true),
      isA<TrailState>().having((s) => s.running, 'running', true),
    ],
  );

  blocTest<TrailCubit, TrailState>(
    'select de etapa aberta põe a escolhida no estado',
    build: () => controller(),
    act: (c) => c.select('t0.notasD'),
    expect: () => [
      isA<TrailState>().having((s) => s.selectedId, 'selectedId', 't0.notasD'),
    ],
  );

  blocTest<TrailCubit, TrailState>(
    'next sem seleção não avisa',
    build: () => controller(),
    act: (c) => c.next(),
    expect: () => <TrailState>[],
  );

  blocTest<TrailCubit, TrailState>(
    'recordDone aprovada emite o progresso e o resultado',
    build: () => controller(),
    act: (c) => c.recordDone(_pct(9, 10)),
    expect: () => [
      isA<TrailState>()
          .having(
            (s) => s.progress.stateOf('t0.notasD'),
            'estado',
            StageState.aprovada,
          )
          .having((s) => s.lastResult?.percent, 'percent', 90)
          .having((s) => s.lastStage?.id, 'etapa', 't0.notasD'),
    ],
  );

  blocTest<TrailCubit, TrailState>(
    'clearResult tira o resultado do resumo',
    build: () => controller(),
    act: (c) async {
      await c.recordDone(_pct(9, 10));
      c.clearResult();
    },
    expect: () => [
      isA<TrailState>(),
      isA<TrailState>()
          .having((s) => s.lastResult, 'resultado', isNull)
          .having((s) => s.lastStage, 'etapa', isNull),
    ],
  );

  blocTest<TrailCubit, TrailState>(
    'skipSelected emite a etapa pulada',
    build: () => controller(),
    act: (c) => c.skipSelected(),
    expect: () => [
      isA<TrailState>().having(
        (s) => s.progress.stateOf('t0.notasD'),
        'estado',
        StageState.pulada,
      ),
    ],
  );
}

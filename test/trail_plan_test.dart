// J03 — Modelo da trilha, desbloqueio e progresso persistente.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/settings/app_settings.dart';
import 'package:zywny/settings/piece_settings.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/trail/trail_progress.dart';
import 'package:zywny/trail/trail_stage.dart';

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

StageResult _pct(int hits, int total) =>
    StageResult(hits: hits, total: total, badMeasures: const {});

void main() {
  group('plano (critérios 1-2)', () {
    test('2 trechos com as duas mãos -> 12+12+3 etapas, ids em ordem', () {
      final track = PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
        _ev(2, 4200),
      ]);
      final plan = TrailPlan.build(_path(6), track, n: 5);
      expect(plan.n, 5);
      expect(plan.stages, hasLength(27));
      expect(
        [for (final s in plan.stages.take(12)) s.id],
        [
          't0.notasD',
          't0.notasE',
          't0.notasJ',
          't0.tempoD.50',
          't0.tempoD.75',
          't0.tempoD.100',
          't0.tempoE.50',
          't0.tempoE.75',
          't0.tempoE.100',
          't0.junto.50',
          't0.junto.75',
          't0.junto.100',
        ],
      );
      expect(plan.stages[12].id, 't1.notasD');
      expect(plan.stages[23].id, 't1.junto.100');
      expect(
        [for (final s in plan.stages.skip(24)) s.id],
        ['final.50', 'final.75', 'final.100'],
      );
      expect(plan.stages.first.startMs, 0);
      expect(plan.stages[11].endMs, 5000);
      expect(plan.stages.last.startMs, 0);
      expect(plan.stages.last.endMs, 6000);
    });

    test('só as etapas e andamentos escolhidos; ids iguais aos do plano '
        'completo', () {
      final track = PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
        _ev(2, 4200),
      ]);
      final plan = TrailPlan.build(
        _path(6),
        track,
        n: 5,
        phases: [TrailPhase.notasJ, TrailPhase.junto],
        speeds: {0.75, 1.0},
      );
      expect(
        [for (final s in plan.stages) s.id],
        [
          't0.notasJ',
          't0.junto.75',
          't0.junto.100',
          't1.notasJ',
          't1.junto.75',
          't1.junto.100',
          'final.50',
          'final.75',
          'final.100',
        ],
      );
    });

    test('na ordem escolhida', () {
      final track = PerformanceTrack.fromEvents([_ev(1, 100), _ev(2, 200)]);
      final plan = TrailPlan.build(
        _path(4),
        track,
        n: 5,
        includeFinal: false,
        phases: [TrailPhase.tempoD, TrailPhase.notasD, TrailPhase.junto],
        speeds: {1.0},
      );
      expect(
        [for (final s in plan.stages) s.id],
        ['t0.tempoD.100', 't0.notasD', 't0.junto.100'],
      );
    });

    test('trecho sem a esquerda -> 4 etapas, sem E nem juntas', () {
      final track = PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
      ]);
      final plan = TrailPlan.build(_path(6), track, n: 5);
      final seg1 = plan.stages.where((s) => s.segment == 1).toList();
      expect(
        [for (final s in seg1) s.id],
        ['t1.notasD', 't1.tempoD.50', 't1.tempoD.75', 't1.tempoD.100'],
      );
      expect(plan.stages.where((s) => s.id.startsWith('t1.notasE')), isEmpty);
      expect(plan.stages.where((s) => s.id.startsWith('t1.junto')), isEmpty);
    });
  });

  group('desbloqueio e melhor (critérios 3-4)', () {
    TrailPlan plan() => TrailPlan.build(
      _path(6),
      PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
        _ev(2, 4200),
      ]),
      n: 5,
    );

    test(
      'atual abre, aprovar/pular avança, pulada que passa vira aprovada',
      () {
        final p = plan();
        var progress = TrailProgress(n: 5, total: p.stages.length);
        expect(progress.current(p)?.id, 't0.notasD');
        expect(progress.isOpen(p, 't0.notasD'), isTrue);
        expect(progress.isOpen(p, 't0.notasE'), isFalse);

        progress = progress.recordResult('t0.notasD', _pct(9, 10));
        expect(progress.stateOf('t0.notasD'), StageState.aprovada);
        expect(progress.current(p)?.id, 't0.notasE');

        progress = progress.skip('t0.notasE');
        expect(progress.stateOf('t0.notasE'), StageState.pulada);
        expect(progress.current(p)?.id, 't0.notasJ');
        expect(progress.doneCount(p), 2);

        progress = progress.recordResult('t0.notasE', _pct(19, 20));
        expect(progress.stateOf('t0.notasE'), StageState.aprovada);
        expect(progress.current(p)?.id, 't0.notasJ');
      },
    );

    test('refazer nunca rebaixa; best só sobe', () {
      const base = TrailProgress(n: 5, total: 27);
      var progress = base.recordResult('t0.notasD', _pct(23, 25));
      expect(progress.stateOf('t0.notasD'), StageState.aprovada);
      expect(progress.records['t0.notasD']?.best, 92);
      progress = progress.recordResult('t0.notasD', _pct(7, 10));
      expect(progress.stateOf('t0.notasD'), StageState.aprovada);
      expect(progress.records['t0.notasD']?.best, 92);
      progress = progress.recordResult('t0.notasD', _pct(97, 100));
      expect(progress.records['t0.notasD']?.best, 97);
    });
  });

  group('store (critérios 5-6)', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('grava e volta igual; JSON estragado vira trilha vazia', () async {
      final store = TrailProgressStore();
      await store.load(const ['012']);
      var progress = const TrailProgress(n: 5, total: 27);
      progress = progress.recordResult('t0.notasD', _pct(9, 10));
      progress = progress.skip('t0.notasE');
      await store.save('012', progress);

      final second = TrailProgressStore();
      await second.load(const ['012']);
      expect(second['012'], progress);
      expect(second.summary('012').done, 2);
      expect(second.summary('012').total, 27);

      await SharedPreferencesAsync().setString('trail_hinos_007', '{quebrado');
      final third = TrailProgressStore();
      await third.load(const ['007']);
      expect(third['007'], TrailProgress.empty);
    });

    test('n diferente não mistura ids', () {
      final track = PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
        _ev(2, 4200),
      ]);
      final plan4 = TrailPlan.build(_path(6), track, n: 4);
      var progress = const TrailProgress(n: 5, total: 27);
      progress = progress.recordResult('t0.notasD', _pct(9, 10));
      expect(progress.current(plan4)?.id, plan4.stages.first.id);
      expect(progress.doneCount(plan4), 0);
      expect(progress.isOpen(plan4, plan4.stages[1].id), isFalse);
    });
  });

  group('trailMeasures (critério 7)', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('geral persiste; fora da faixa volta para >= 3', () async {
      final first = AppSettings();
      await first.load();
      expect(first.trailMeasures, kTrailDefaultMeasures);
      first.trailMeasures = 7;
      await pumpEventQueue();
      final second = AppSettings();
      await second.load();
      expect(second.trailMeasures, 7);

      await SharedPreferencesAsync().setInt('trail_measures', 1);
      final third = AppSettings();
      await third.load();
      expect(third.trailMeasures, kTrailMinMeasures);
    });

    test('por hino persiste; fora da faixa volta para >= 3', () async {
      final store = PieceSettingsStore();
      await store.save('hinos', '005', const PieceSettings(trailMeasures: 8));
      expect((await store.load('hinos', '005')).trailMeasures, 8);
      expect((await store.load('hinos', '005')).isDefault, isFalse);
      expect((await store.load('hinos', '006')).trailMeasures, isNull);

      final clamped = PieceSettings.fromJson({'trailMeasures': 1});
      expect(clamped.trailMeasures, kTrailMinMeasures);
    });

    test('efetivo é o da música, senão o geral', () {
      expect(effectiveTrailMeasures(general: 5, piece: null), 5);
      expect(effectiveTrailMeasures(general: 5, piece: 8), 8);
    });
  });
}

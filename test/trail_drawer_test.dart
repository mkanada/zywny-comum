// J06 — Gaveta da trilha: lista, refazer, pular, reiniciar e N.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/settings/hymn_settings.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_controller.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/trail/trail_progress.dart';
import 'package:zywny/trail/trail_widgets.dart';

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

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('TrailDrawer (critério 1)', () {
    Future<void> pumpDrawer(
      WidgetTester tester, {
      required TrailPlan plan,
      required TrailProgress progress,
      ValueChanged<String>? onSelect,
      VoidCallback? onSkip,
      VoidCallback? onRestart,
      ValueChanged<String>? onRepeat,
    }) => tester.pumpWidget(
      _app(
        TrailDrawer(
          plan: plan,
          progress: progress,
          selectedId: progress.current(plan)?.id,
          currentId: progress.current(plan)?.id,
          onClose: () {},
          onSelectStage: onSelect ?? (_) {},
          onSkipCurrent: onSkip ?? () {},
          onRestartTrail: onRestart ?? () {},
          onRepeatStage: onRepeat,
        ),
      ),
    );

    testWidgets('repetir: só nas feitas (aprovada ou pulada)', (tester) async {
      final plan = _plan();
      var progress = TrailProgress(n: 5, total: plan.stages.length);
      progress = progress.recordResult(
        't0.notasD',
        const StageResult(hits: 23, total: 25, badMeasures: {}),
      );
      progress = progress.skip('t0.notasE');
      final repeated = <String>[];
      await pumpDrawer(
        tester,
        plan: plan,
        progress: progress,
        onRepeat: repeated.add,
      );
      expect(find.byTooltip('Repetir etapa'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Repetir etapa').first);
      await tester.pump();
      expect(repeated, ['t0.notasD']);

      // Sem retorno (etapa rodando): sem botão.
      await pumpDrawer(tester, plan: plan, progress: progress);
      expect(find.byTooltip('Repetir etapa'), findsNothing);
    });

    testWidgets('o cabeçalho mostra o todo: barra e "N de M etapas" (U13)', (
      tester,
    ) async {
      final plan = _plan();
      var progress = TrailProgress(n: 5, total: plan.stages.length);
      // Duas etapas aprovadas e uma pulada, na ordem do plano.
      progress = progress.recordResult(
        plan.stages[0].id,
        const StageResult(hits: 19, total: 20, badMeasures: {}),
      );
      progress = progress.recordResult(
        plan.stages[1].id,
        const StageResult(hits: 19, total: 20, badMeasures: {}),
      );
      progress = progress.recordResult(
        plan.stages[2].id,
        const StageResult(hits: 1, total: 20, badMeasures: {}),
      );
      await pumpDrawer(tester, plan: plan, progress: progress);
      final done = progress.doneCount(plan);
      expect(
        find.textContaining('$done de ${plan.stages.length} etapas'),
        findsOneWidget,
      );
      expect(find.byType(TrailProgressBar), findsOneWidget);
    });

    testWidgets('trechos com feitas/total; atual expande; trancada não abre', (
      tester,
    ) async {
      final plan = _plan();
      final progress = TrailProgress(n: 5, total: plan.stages.length);
      var selected = '';
      await pumpDrawer(
        tester,
        plan: plan,
        progress: progress,
        onSelect: (id) => selected = id,
      );
      expect(find.text('Trecho 1 · compassos 1–5 · 0/12'), findsOneWidget);
      // O resto da lista (rolável) é montado sob demanda: rola até lá.
      await tester.scrollUntilVisible(
        find.text('Trecho 2 · compassos 5–6 · 0/12'),
        200,
      );
      expect(find.text('Trecho 2 · compassos 5–6 · 0/12'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Fase final'), 200);
      expect(find.text('Fase final'), findsOneWidget);
      expect(find.text('em breve'), findsOneWidget);
      // Volta ao trecho atual para tocar nas etapas.
      await tester.scrollUntilVisible(find.text('Notas da direita'), -200);
      // O trecho atual vem expandido (12 etapas à vista); o outro, fechado.
      expect(find.text('Notas da direita'), findsOneWidget);
      expect(find.text('Tudo junto no ritmo 100%'), findsOneWidget);
      expect(find.text('atual'), findsOneWidget);
      // Trancada não responde; a atual, sim.
      await tester.tap(find.text('Notas da esquerda'));
      await tester.pump();
      expect(selected, '');
      await tester.tap(find.text('Notas da direita'));
      await tester.pump();
      expect(selected, 't0.notasD');
      // O resto da lista (rolável) é montado sob demanda: rola até lá.
      await tester.scrollUntilVisible(
        find.text('Trecho 2 · compassos 5–6 · 0/12'),
        200,
      );
    });

    testWidgets('aprovada mostra %; pulada, a marca', (tester) async {
      final plan = _plan();
      var progress = TrailProgress(n: 5, total: plan.stages.length);
      progress = progress.recordResult(
        't0.notasD',
        const StageResult(hits: 23, total: 25, badMeasures: {}),
      );
      progress = progress.skip('t0.notasE');
      await pumpDrawer(tester, plan: plan, progress: progress);
      expect(find.text('Trecho 1 · compassos 1–5 · 2/12'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('pulada'), findsOneWidget);
    });

    testWidgets('pular e reiniciar (com confirmação)', (tester) async {
      final plan = _plan();
      final progress = TrailProgress(n: 5, total: plan.stages.length);
      var skips = 0;
      var restarts = 0;
      await pumpDrawer(
        tester,
        plan: plan,
        progress: progress,
        onSkip: () => skips++,
        onRestart: () => restarts++,
      );
      await tester.tap(find.text('Pular etapa atual'));
      expect(skips, 1);
      await tester.tap(find.text('Reiniciar trilha'));
      await tester.pumpAndSettle();
      expect(find.text('Reiniciar trilha?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(restarts, 0);
      await tester.tap(find.text('Reiniciar trilha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reiniciar'));
      await tester.pumpAndSettle();
      expect(restarts, 1);
    });
  });

  group('refazer com a gaveta (critério 2)', () {
    testWidgets('pior mantém, melhor sobe', (tester) async {
      final plan = _plan();
      final store = TrailProgressStore();
      final controller = TrailController(
        path: _path(6),
        plan: plan,
        progress: TrailProgress(n: 5, total: plan.stages.length),
        store: store,
        hymnNumber: 12,
      );
      await controller.recordDone(
        const StageResult(hits: 19, total: 20, badMeasures: {}),
      );
      controller.next();
      await tester.pumpWidget(
        _app(
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TrailDrawer(
              plan: plan,
              progress: controller.progress,
              selectedId: controller.selected?.id,
              currentId: controller.progress.current(plan)?.id,
              onClose: () {},
              onSelectStage: controller.select,
              onSkipCurrent: () {},
              onRestartTrail: () {},
            ),
          ),
        ),
      );
      // Refaz a aprovada com nota pior: continua aprovada com a melhor %.
      await tester.tap(find.text('Notas da direita').first);
      await tester.pump();
      expect(controller.selected?.id, 't0.notasD');
      await controller.recordDone(
        const StageResult(hits: 7, total: 10, badMeasures: {0}),
      );
      expect(
        controller.progress.records['t0.notasD'],
        const StageRecord(state: StageState.aprovada, best: 95),
      );
      await tester.pump();
      expect(find.text('95%'), findsOneWidget);
      // Com nota melhor, a % sobe.
      await controller.recordDone(
        const StageResult(hits: 97, total: 100, badMeasures: {}),
      );
      expect(controller.progress.records['t0.notasD']?.best, 97);
    });
  });

  group('TrailNSelector e confirmação', () {
    testWidgets('mostra o valor e muda de um em um, com limites', (
      tester,
    ) async {
      var value = 5;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => TrailNSelector(
              value: value,
              max: 7,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byTooltip('Mais compassos por trecho'));
      await tester.pump();
      expect(value, 6);
      await tester.tap(find.byTooltip('Menos compassos por trecho'));
      await tester.pump();
      expect(value, 5);
    });

    testWidgets('no mínimo e no máximo, o botão desliga', (tester) async {
      await tester.pumpWidget(
        _app(const TrailNSelector(value: 3, max: 7, onChanged: _noop)),
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(
        _app(const TrailNSelector(value: 7, max: 7, onChanged: _noop)),
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull,
      );
    });

    testWidgets('confirmTrailReset: cancelar nega, confirmar aceita', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SizedBox()));
      Future<bool> ask() => confirmTrailReset(
        tester.element(find.byType(Scaffold)),
        title: 'Trocar o corte?',
        message: 'Isto reinicia a trilha deste hino.',
        confirmLabel: 'Trocar',
      );
      var future = ask();
      await tester.pumpAndSettle();
      expect(find.text('Trocar o corte?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);

      future = ask();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trocar'));
      await tester.pumpAndSettle();
      expect(await future, isTrue);
    });
  });

  group('N e reinício (critérios 3-5)', () {
    test('reiniciar zera só aquele hino', () async {
      final store = TrailProgressStore();
      const full = TrailProgress(
        n: 5,
        total: 24,
        records: {
          't0.notasD': StageRecord(state: StageState.aprovada, best: 90),
        },
      );
      await store.save(12, full);
      await store.save(13, full);
      await store.reset(12);
      expect(store[12], TrailProgress.empty);
      expect(store[13], full);
    });

    test('usar o padrão volta ao N geral', () async {
      final store = HymnSettingsStore();
      await store.save(5, const HymnSettings(trailMeasures: 8));
      expect((await store.load(5)).trailMeasures, 8);
      await store.save(5, const HymnSettings());
      final reloaded = await store.load(5);
      expect(reloaded.trailMeasures, isNull);
      expect(reloaded.isDefault, isTrue);
      expect(
        await SharedPreferencesAsync().getString('hymn_settings_5'),
        isNull,
      );
    });
  });
  group('reforço na gaveta (J07)', () {
    TrailPlan fullPlan() => TrailPlan.build(
      _path(6),
      PerformanceTrack.fromEvents([
        _ev(1, 100),
        _ev(2, 200),
        _ev(1, 4100),
        _ev(2, 4200),
      ]),
      n: 5,
    );

    testWidgets('fase final lista os blocos', (tester) async {
      final plan = fullPlan();
      var progress = TrailProgress(n: 5, total: plan.stages.length);
      for (final s in plan.stages) {
        if (s.segment != null) {
          progress = progress.recordResult(
            s.id,
            const StageResult(hits: 19, total: 20, badMeasures: {}),
          );
        }
      }
      await tester.pumpWidget(
        _app(
          TrailDrawer(
            plan: plan,
            progress: progress,
            selectedId: 'final.50',
            currentId: 'final.50',
            onClose: () {},
            onSelectStage: (_) {},
            onSkipCurrent: () {},
            onRestartTrail: () {},
            blocks: const [
              ReinforcementView(
                first: 1,
                last: 2,
                state: StageState.pendente,
                isCurrent: true,
              ),
              ReinforcementView(
                first: 5,
                last: 5,
                state: StageState.pulada,
                isCurrent: false,
              ),
            ],
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('Fase final · 0/3'), 200);
      expect(find.text('Reforço 1 · compassos 2–3'), findsOneWidget);
      expect(find.text('Reforço 2 · compassos 6–6'), findsOneWidget);
    });
  });
}

void _noop(int _) {}

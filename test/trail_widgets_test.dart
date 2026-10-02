// J05 — Faixa da trilha e resumo da etapa (widgets com controlador falso).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_progress.dart';
import 'package:zywny/trail/trail_widgets.dart';
import 'package:zywny/ui/phone_chrome.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('texto da faixa', () {
    test('trecho e estado', () {
      expect(
        trailStripTextFor(6, 1, 'Notas juntas'),
        'Trecho 2/6 · Notas juntas',
      );
      expect(
        trailStripTextFor(6, null, 'Tudo junto no ritmo 100%'),
        'Fase final · Tudo junto no ritmo 100%',
      );
      const empty = TrailProgress(n: 5, total: 1);
      expect(trailStateText(empty, 't0.notasD'), '');
      const done = TrailProgress(
        n: 5,
        total: 2,
        records: {
          'a': StageRecord(state: StageState.aprovada, best: 92),
          'b': StageRecord(state: StageState.pulada, best: 0),
        },
      );
      expect(trailStateText(done, 'a'), '92%');
      expect(trailStateText(done, 'b'), 'pulada');
    });
  });

  group('TrailStrip', () {
    testWidgets('mostra texto e estado, começar/parar chamam de volta', (
      tester,
    ) async {
      var starts = 0;
      var stops = 0;
      await tester.pumpWidget(
        _app(
          TrailStrip(
            text: 'Trecho 2/6 · Notas juntas',
            stateText: '92%',
            running: false,
            onStart: () => starts++,
            onStop: () => stops++,
          ),
        ),
      );
      expect(find.textContaining('Trecho 2/6'), findsOneWidget);
      expect(find.textContaining('92%'), findsOneWidget);
      expect(tester.getSize(find.byType(TrailStrip)).height, 34);
      await tester.tap(find.byTooltip('Começar etapa'));
      expect(starts, 1);

      await tester.pumpWidget(
        _app(
          TrailStrip(
            text: 'Trecho 2/6 · Notas juntas',
            stateText: '',
            running: true,
            onStart: () => starts++,
            onStop: () => stops++,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Parar etapa'));
      expect(stops, 1);
    });
  });

  group('TrailTitleChip na barra do título', () {
    for (final size in const [Size(844, 390), Size(640, 360)]) {
      testWidgets(
        'título longo em ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var taps = 0;
          await tester.pumpWidget(
            _app(
              PhoneTitleBar(
                number: 123,
                title: 'Um título de hino bem comprido que passa de quarenta',
                onBack: () {},
                center: TrailTitleChip(
                  text: 'Trecho 2/6 · Tudo junto no ritmo 75%',
                  stateText: '98%',
                  onTap: () => taps++,
                ),
                trailing: const [PhoneStatusPill(text: 'Esperando · mão dir.')],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.textContaining('Trecho 2/6'));
          expect(taps, 1);
        },
      );
    }
  });

  group('showStageSummary', () {
    Future<StageSummaryAction?> show(
      WidgetTester tester, {
      required int percent,
      required bool last,
    }) => showStageSummary(
      tester.element(find.byType(Scaffold)),
      stageRef: 'Trecho 1/4 · Notas da direita',
      result: StageResult(hits: percent, total: 100, badMeasures: const {6}),
      badLogical: const [7],
      isLast: last,
    );

    testWidgets('aprovado: próxima ou repetir', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      final future = show(tester, percent: 95, last: false);
      await tester.pumpAndSettle();
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('Aprovado · meta 90%'), findsOneWidget);
      expect(
        find.text('Erros no compasso 7 — marcados na partitura.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Próxima etapa'));
      await tester.pumpAndSettle();
      expect(await future, StageSummaryAction.next);
    });

    testWidgets('aprovado no último: concluir', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      final future = show(tester, percent: 100, last: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();
      expect(await future, StageSummaryAction.next);
    });

    testWidgets('reprovado com reforço: treinar os trechos com erro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SizedBox()));
      final future = showStageSummary(
        tester.element(find.byType(Scaffold)),
        stageRef: 'Fase final · Tudo junto no ritmo 50%',
        result: const StageResult(hits: 17, total: 20, badMeasures: {7}),
        badLogical: const [8],
        isLast: false,
        blockCount: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Tentar de novo'), findsNothing);
      await tester.tap(find.text('Treinar os trechos com erro (2)'));
      await tester.pumpAndSettle();
      expect(await future, StageSummaryAction.train);
    });

    testWidgets('conclusão: biblioteca ou treino livre', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      Future<TrailConclusionAction?> conclude() =>
          showTrailConclusion(tester.element(find.byType(Scaffold)));
      var future = conclude();
      await tester.pumpAndSettle();
      expect(find.text('Trilha concluída!'), findsOneWidget);
      await tester.tap(find.text('Voltar à biblioteca'));
      await tester.pumpAndSettle();
      expect(await future, TrailConclusionAction.library);

      future = conclude();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar em treino livre'));
      await tester.pumpAndSettle();
      expect(await future, TrailConclusionAction.free);
    });

    testWidgets('reprovado: tentar de novo ou pular com confirmação', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SizedBox()));
      var future = show(tester, percent: 85, last: false);
      await tester.pumpAndSettle();
      expect(find.text('Precisa de 90% para passar'), findsOneWidget);
      expect(find.textContaining('Faltou'), findsNothing);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(await future, StageSummaryAction.retry);

      future = show(tester, percent: 70, last: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pular etapa'));
      await tester.pumpAndSettle();
      expect(find.text('Pular etapa?'), findsOneWidget);
      await tester.tap(find.text('Continuar aqui'));
      await tester.pumpAndSettle();
      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Pular etapa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(await future, StageSummaryAction.skip);
    });
  });
}

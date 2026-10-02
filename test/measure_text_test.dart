// U12 — frases dos resumos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/practice/measure_text.dart';
import 'package:zywny/practice/practice_report.dart';
import 'package:zywny/practice/practice_session.dart';
import 'package:zywny/practice/practice_tools.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_widgets.dart';

/// Um relatório com [n] notas `correct` e `late`/`early` de [deltaMs] cada,
/// em ms de parede (andamento 1).
PracticeReport _report(List<double> deltas) => PracticeReport([
  for (var i = 0; i < deltas.length; i++)
    ReportEntry(
      NoteVerdict(
        eventId: 'n$i',
        pitch: 60,
        kind: PracticeVerdictKind.correct,
        deltaMs: deltas[i],
        velocity: 80,
      ),
      i % 3,
    ),
]);

void main() {
  group('joinMeasureNumbers', () {
    test('faixas de três ou mais e o resto solto', () {
      expect(joinMeasureNumbers([1, 2, 3, 6]), '1 a 3 e 6');
      expect(joinMeasureNumbers([6, 8]), '6 e 8');
      expect(joinMeasureNumbers([1, 2]), '1 e 2');
      expect(joinMeasureNumbers([4]), '4');
      expect(joinMeasureNumbers([1, 2, 3, 4, 5]), '1 a 5');
      expect(joinMeasureNumbers([1, 4, 9]), '1, 4 e 9');
      expect(joinMeasureNumbers([]), '');
    });

    test('sem faixas, na ordem dada', () {
      expect(joinMeasureNumbers([4, 1, 2], ranges: false), '4, 1 e 2');
      expect(joinMeasureNumbers([1, 2, 3], ranges: false), '1, 2 e 3');
    });
  });

  group('practiceTimingPhrase', () {
    test('no tempo, atrasado, adiantado e irregular', () {
      expect(practiceTimingPhrase(_report([0, 0, 0, 0])), 'No tempo.');
      expect(practiceTimingPhrase(_report([20, 20, 20])), 'No tempo.');
      expect(
        practiceTimingPhrase(_report([50, 50, 50])),
        'Você está entrando atrasado.',
      );
      expect(
        practiceTimingPhrase(_report([-50, -50, -50])),
        'Você está entrando adiantado.',
      );
      // Média 0, desvio 80: no tempo, mas o pulso balança.
      expect(
        practiceTimingPhrase(_report([80, -80, 80, -80])),
        'No tempo. O pulso está irregular.',
      );
      expect(
        practiceTimingPhrase(_report([150, 10, 150, 10])),
        'Você está entrando atrasado. O pulso está irregular.',
      );
    });
  });

  group('resumos', () {
    Future<void> open(
      WidgetTester tester,
      Widget Function(BuildContext) go,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => go(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('resumo do treino livre: sem "ms" até abrir "Detalhes"', (
      tester,
    ) async {
      final report = _report([120, 100, 90, 110]);
      await open(tester, (context) {
        showPracticeSummary(context, report);
        return const SizedBox();
      });
      expect(find.textContaining('Precisão'), findsOneWidget);
      expect(find.text('Você está entrando atrasado.'), findsOneWidget);
      expect(find.textContaining('ms'), findsNothing);

      await tester.tap(find.text('Detalhes'));
      await tester.pumpAndSettle();
      expect(find.textContaining(' ms'), findsWidgets);
      await tester.tap(find.text('Esconder detalhes'));
      await tester.pumpAndSettle();
      expect(find.textContaining(' ms'), findsNothing);
    });

    testWidgets('resumo da etapa: erros em 1, 2, 3 e 6 → "1 a 3 e 6"', (
      tester,
    ) async {
      await open(tester, (context) {
        showStageSummary(
          context,
          stageRef: 'Trecho 1/3',
          result: const StageResult(hits: 6, total: 10, badMeasures: {}),
          badLogical: const [1, 2, 3, 6],
          isLast: false,
        );
        return const SizedBox();
      });
      expect(
        find.text('Erros nos compassos 1 a 3 e 6 — marcados na partitura.'),
        findsOneWidget,
      );
    });

    testWidgets('resumo da etapa sem erros', (tester) async {
      await open(tester, (context) {
        showStageSummary(
          context,
          stageRef: 'Trecho 1/3',
          result: const StageResult(hits: 10, total: 10, badMeasures: {}),
          badLogical: const [],
          isLast: false,
        );
        return const SizedBox();
      });
      expect(find.text('Nenhum compasso com erro.'), findsOneWidget);
    });
  });
}

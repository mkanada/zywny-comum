// U18 — painel lateral da partitura no celular.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/trail/stage_result.dart';
import 'package:zywny/trail/trail_widgets.dart';
import 'package:zywny/ui/side_panel.dart';

void main() {
  void landscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester,
    Future<Object?> Function(BuildContext) go,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              // A "pauta": ocupa a tela toda; o painel entra por cima.
              const Expanded(child: ColoredBox(color: Colors.white)),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => go(context),
                  child: const Text('abrir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('o resumo da etapa entra pela direita e a metade esquerda '
      'fica livre', (tester) async {
    landscape(tester);
    await open(
      tester,
      (context) => showStageSummary(
        context,
        stageRef: 'Trecho 1/3',
        result: const StageResult(hits: 6, total: 10, badMeasures: {}),
        badLogical: const [2, 3],
        isLast: false,
        sidePanel: true,
      ),
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Resumo da etapa'), findsOneWidget);
    final panel = tester.getRect(find.byType(PhoneSidePanel));
    // O painel ocupa a tela inteira (a casca), mas o que se vê dele — o
    // título e o conteúdo — está na metade direita.
    final title = tester.getRect(find.text('Resumo da etapa'));
    expect(title.left, greaterThan(panel.width / 2));
    final text = tester.getRect(
      find.textContaining('Erros nos compassos 2 e 3'),
    );
    expect(text.left, greaterThan(panel.width / 2));
    // Sem escurecer a pauta: nenhuma cortina de tela cheia.
    expect(
      find.descendant(
        of: find.byType(PhoneSidePanel),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color.a > 0 && w.color.a < 1,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('"Ir para o compasso" devolve o compasso escolhido', (
    tester,
  ) async {
    landscape(tester);
    int? chosen;
    await open(tester, (context) async {
      var target = 3;
      chosen = await showSheetOrSidePanel<int>(
        context,
        sidePanel: true,
        title: 'Ir para o compasso',
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => sheetBody(
            sidePanel: true,
            child: Column(
              children: [
                Text('compasso $target'),
                TextButton(
                  onPressed: () => setState(() => target++),
                  child: const Text('mais'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, target),
                  child: const Text('Ir'),
                ),
              ],
            ),
          ),
        ),
      );
      return chosen;
    });
    await tester.tap(find.text('mais'));
    await tester.pump();
    await tester.tap(find.text('Ir'));
    await tester.pumpAndSettle();
    expect(chosen, 4);
    expect(find.byType(PhoneSidePanel), findsNothing);
  });

  testWidgets('o "voltar" do aparelho fecha o painel; tocar na pauta também', (
    tester,
  ) async {
    landscape(tester);
    await open(
      tester,
      (context) => showPhoneSidePanel<void>(
        context,
        title: 'Painel',
        builder: (context) => const Text('corpo'),
      ),
    );
    expect(find.text('corpo'), findsOneWidget);
    await tester.binding.handlePopRoute(); // o "voltar" do Android
    await tester.pumpAndSettle();
    expect(find.text('corpo'), findsNothing);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('corpo'), findsOneWidget);
    await tester.tapAt(const Offset(40, 200)); // na pauta, à esquerda
    await tester.pumpAndSettle();
    expect(find.text('corpo'), findsNothing);
  });

  testWidgets('fora do celular, a folha inferior de sempre', (tester) async {
    landscape(tester);
    await open(
      tester,
      (context) => showStageSummary(
        context,
        stageRef: 'Trecho 1/3',
        result: const StageResult(hits: 6, total: 10, badMeasures: {}),
        badLogical: const [],
        isLast: false,
      ),
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PhoneSidePanel), findsNothing);
  });
}

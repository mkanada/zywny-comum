import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/bug_report_builder.dart';
import 'package:zywny_comum/diag/bug_report_delivery.dart';
import 'package:zywny_comum/diag/bug_report_scope.dart';
import 'package:zywny_comum/diag/diag_screens.dart';
import 'package:zywny_diag/diag_log.dart';

class _Ticking extends StatefulWidget {
  const _Ticking();

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, _) => Text('v=${c.value.toStringAsFixed(2)}'),
  );
}

/// `BugReportScope.start` e a captura da tela, que usa o motor de verdade
/// (fora do relógio falso dos testes).
Future<void> openReport(WidgetTester tester) async {
  unawaited(BugReportScope.start());
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(DiagLog.reset);

  group('o arquivo', () {
    BugReportInput input({Uint8List? shot}) => BugReportInput(
      appName: 'aprendizado',
      appVersion: '1.2.3 (4)',
      at: DateTime(2026, 10, 23, 15, 30, 12),
      doing: 'tocando o 34d',
      happened: 'a nota certa ficou vermelha',
      device: const {'plataforma': 'android'},
      routes: const ['tela: exercicio 34d'],
      stateJson: '{"audio": {}}',
      logs: const [DiagLogFile('s00001.log', 'linha\n')],
      screenshotPng: shot,
    );

    test('o nome leva o app e a hora', () {
      expect(
        bugReportFileName('aprendizado', DateTime(2026, 10, 23, 9, 5, 7)),
        'zywny-bug-aprendizado-20261023-090507.zip',
      );
    });

    test('o zip leva texto, estado, captura e logs', () {
      final zip = ZipDecoder().decodeBytes(
        buildBugReportZip(input(shot: Uint8List.fromList([1, 2, 3]))),
      );
      expect(zip.map((f) => f.name).toSet(), {
        'relatorio.txt',
        'estado.json',
        'captura.png',
        'logs/s00001.log',
      });
      final text = String.fromCharCodes(
        zip.findFile('relatorio.txt')!.content as List<int>,
      );
      expect(text, contains('tocando o 34d'));
      expect(text, contains('a nota certa ficou vermelha'));
      expect(text, contains('tela: exercicio 34d'));
    });

    test('sem captura o zip não leva a imagem', () {
      final zip = ZipDecoder().decodeBytes(buildBugReportZip(input()));
      expect(zip.findFile('captura.png'), isNull);
    });
  });

  testWidgets('reportar para a tela e o som, gera o arquivo e entrega', (
    tester,
  ) async {
    await DiagLog.init(storage: MemoryDiagStorage(), installHandlers: false);
    var frozen = 0;
    DiagLog.addFreezeHook(() => frozen++);
    String? delivered;
    Uint8List? bytes;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [DiagScreens.observer],
        builder: (context, child) => BugReportScope(
          appName: 'teste',
          deliver: (name, data) async {
            delivered = name;
            bytes = data;
            return BugReportDelivery(savedAt: '/x/$name');
          },
          child: child!,
        ),
        home: const Scaffold(
          body: DiagSessionScope(
            kind: 'exercicio',
            name: '34d',
            child: Center(child: _Ticking()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final before = tester.widget<Text>(find.textContaining('v=')).data;
    DiagLog.log('nota', 'on 60');

    await openReport(tester);
    expect(frozen, 1);

    // As animações pararam e a tela do relatório está por cima.
    expect(find.text('Reportar um bug'), findsOneWidget);
    final after = tester.widget<Text>(find.textContaining('v=')).data;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Text>(find.textContaining('v=')).data, after);
    expect(after, isNotNull);
    expect(before, isNot(isEmpty));

    await tester.enterText(
      find.widgetWithText(TextField, 'O que você estava fazendo?'),
      'tocando',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'O que aconteceu (o erro)?'),
      'travou',
    );
    await tester.tap(find.text('Gerar relatório'));
    await tester.pumpAndSettle();

    expect(delivered, startsWith('zywny-bug-teste-'));
    expect(find.text('Relatório pronto'), findsOneWidget);
    final zip = ZipDecoder().decodeBytes(bytes!);
    final names = zip.map((f) => f.name).toList();
    expect(names, containsAll(['relatorio.txt', 'estado.json']));
    expect(names.any((n) => n.startsWith('logs/')), isTrue);
    final text = String.fromCharCodes(
      zip.findFile('relatorio.txt')!.content as List<int>,
    );
    expect(text, contains('travou'));
    expect(text, contains('exercicio 34d'));

    await tester.tap(find.text('Fechar'));
    await tester.pump();
    expect(find.text('Reportar um bug'), findsNothing);
  });

  testWidgets('cancelar volta a tela a andar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            BugReportScope(appName: 'teste', child: child!),
        home: const Scaffold(body: Center(child: _Ticking())),
      ),
    );
    await openReport(tester);
    final frozenText = tester.widget<Text>(find.textContaining('v=')).data;
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Text>(find.textContaining('v=')).data,
      isNot(frozenText),
    );
  });

  testWidgets('três dedos parados abrem o relatório', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            BugReportScope(appName: 'teste', child: child!),
        home: const Scaffold(body: Center(child: Text('oi'))),
      ),
    );
    final center = tester.getCenter(find.text('oi'));
    final fingers = [
      await tester.startGesture(center - const Offset(60, 0)),
      await tester.startGesture(center),
      await tester.startGesture(center + const Offset(60, 0)),
    ];
    await tester.pump(kBugReportHold + const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reportar um bug'), findsOneWidget);
    for (final f in fingers) {
      await f.up();
    }
  });

  testWidgets('dois dedos não abrem', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            BugReportScope(appName: 'teste', child: child!),
        home: const Scaffold(body: Center(child: Text('oi'))),
      ),
    );
    final center = tester.getCenter(find.text('oi'));
    final a = await tester.startGesture(center - const Offset(60, 0));
    final b = await tester.startGesture(center);
    await tester.pump(kBugReportHold * 2);
    expect(find.text('Reportar um bug'), findsNothing);
    await a.up();
    await b.up();
  });
}

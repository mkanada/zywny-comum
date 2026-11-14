import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/audio_recording_corner.dart';
import 'package:zywny_comum/diag/audio_recording_service.dart';
import 'package:zywny_comum/diag/bug_report_builder.dart';
import 'package:zywny_comum/diag/bug_report_delivery.dart';
import 'package:zywny_comum/diag/bug_report_scope.dart';
import 'package:zywny_comum/diag/bug_report_sender.dart';
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

class _FakeSender implements BugReportSender {
  _FakeSender({this.available = true, this.failWith});

  final bool available;
  final Object? failWith;
  BugReportUpload? got;

  @override
  bool get isAvailable => available;

  @override
  Future<BugReportReceipt> send(BugReportUpload upload) async {
    if (failWith != null) throw failWith!;
    got = upload;
    return const BugReportReceipt('ABC123');
  }
}

Widget _app(BugReportSender? sender) => MaterialApp(
  builder: (context, child) => BugReportScope(
    appName: 'teste',
    sender: sender,
    deliver: (name, data) async => BugReportDelivery(savedAt: '/x/$name'),
    child: child!,
  ),
  home: const Scaffold(body: Center(child: Text('home'))),
);

class _FakeRecorder implements AudioRecordingService {
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> start() async {
    starts++;
    return true;
  }

  @override
  Future<AudioRecordingResult?> stop() async {
    stops++;
    return const AudioRecordingResult(savedAt: 'Download/Zywny/a.m4a');
  }

  @override
  Future<void> dispose() async {}
}

/// Segura o dedo no canto da gravação o bastante para ligar/desligar.
Future<void> _holdCorner(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(kAudioRecordingHold + const Duration(milliseconds: 50));
  await g.up();
  await tester.pump();
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

  testWidgets('parar a gravação abre o relatório, com a sessão no log', (
    tester,
  ) async {
    await DiagLog.init(storage: MemoryDiagStorage(), installHandlers: false);
    final rec = _FakeRecorder();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BugReportScope(
          appName: 'teste',
          recorder: rec,
          deliver: (name, data) async => BugReportDelivery(savedAt: '/x/$name'),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('tela'))),
      ),
    );
    final corner =
        tester.getBottomLeft(find.byType(MaterialApp)) + const Offset(20, -20);

    await _holdCorner(tester, corner);
    expect(rec.starts, 1);
    expect(find.text('Reportar um bug'), findsNothing);

    await _holdCorner(tester, corner);
    expect(rec.stops, 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));

    expect(find.text('Reportar um bug'), findsOneWidget);
    final gravacao = DiagLog.collect().singleWhere(
      (f) => f.text.contains('#sessao tipo=gravacao'),
    );
    expect(gravacao.text, contains('fim: gravacao microfone'));
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

  group('enviar à equipe', () {
    setUp(() async {
      await DiagLog.init(storage: MemoryDiagStorage(), installHandlers: false);
    });

    // A tela do relatório é uma lista: numa janela alta o botão está à vista.
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('sem envio disponível, só gera o arquivo', (tester) async {
      tall(tester);
      await tester.pumpWidget(_app(_FakeSender(available: false)));
      await tester.pump(const Duration(seconds: 1));
      await openReport(tester);
      expect(find.text('Gerar relatório'), findsOneWidget);
      expect(find.text('Enviar à equipe'), findsNothing);
    });

    testWidgets('envia o zip e o texto e mostra o código', (tester) async {
      final sender = _FakeSender();
      tall(tester);
      await tester.pumpWidget(_app(sender));
      await tester.pump(const Duration(seconds: 1));
      await openReport(tester);
      expect(find.text('Só gerar o arquivo'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'O que você estava fazendo?'),
        'tocando',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'O que aconteceu (o erro)?'),
        'travou',
      );
      await tester.tap(find.text('Enviar à equipe'));
      await tester.pumpAndSettle();

      final up = sender.got!;
      expect(up.appName, 'teste');
      expect(up.doing, 'tocando');
      expect(up.happened, 'travou');
      expect(up.fileName, startsWith('zywny-bug-teste-'));
      final zip = ZipDecoder().decodeBytes(up.zip);
      expect(zip.map((f) => f.name), contains('relatorio.txt'));
      expect(up.zip.length, lessThanOrEqualTo(kBugReportMaxUploadBytes));
      expect(find.text('Relatório enviado'), findsOneWidget);
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('o motivo da recusa vai para a tela e dá para tentar de novo', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        _app(_FakeSender(failWith: const BugReportSendException('Muitos.'))),
      );
      await tester.pump(const Duration(seconds: 1));
      await openReport(tester);
      await tester.tap(find.text('Enviar à equipe'));
      await tester.pumpAndSettle();
      expect(find.text('Muitos.'), findsOneWidget);
      expect(find.text('Enviar à equipe'), findsOneWidget);
    });

    testWidgets('erro de rede dá a mensagem genérica', (tester) async {
      tall(tester);
      await tester.pumpWidget(_app(_FakeSender(failWith: StateError('x'))));
      await tester.pump(const Duration(seconds: 1));
      await openReport(tester);
      await tester.tap(find.text('Enviar à equipe'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não consegui enviar agora'), findsOneWidget);
    });

    testWidgets(
      'sendNow envia com os textos prontos e sem a tela do relatório',
      (tester) async {
        final sender = _FakeSender();
        await tester.pumpWidget(_app(sender));
        await tester.pump(const Duration(seconds: 1));
        expect(BugReportScope.canSend, isTrue);

        late BugReportReceipt receipt;
        await tester.runAsync(() async {
          receipt = await BugReportScope.sendNow(
            doing: 'Treinando o 34d',
            happened: 'Errei o compasso 5',
          );
        });
        expect(receipt.id, 'ABC123');
        final up = sender.got!;
        expect(up.doing, 'Treinando o 34d');
        expect(up.happened, 'Errei o compasso 5');
        final zip = ZipDecoder().decodeBytes(up.zip);
        expect(
          zip.map((f) => f.name),
          containsAll(['relatorio.txt', 'estado.json']),
        );
        final text = String.fromCharCodes(
          zip.findFile('relatorio.txt')!.content as List<int>,
        );
        expect(text, contains('Errei o compasso 5'));
        // Não abriu a tela do relatório nem congelou nada.
        expect(find.text('Reportar um bug'), findsNothing);
      },
    );

    testWidgets('sendNow sem envio disponível diz o motivo', (tester) async {
      await tester.pumpWidget(_app(_FakeSender(available: false)));
      await tester.pump(const Duration(seconds: 1));
      expect(BugReportScope.canSend, isFalse);
      await expectLater(
        BugReportScope.sendNow(doing: 'a', happened: 'b'),
        throwsA(isA<BugReportSendException>()),
      );
    });
  });
}

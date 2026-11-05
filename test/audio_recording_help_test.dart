// Configurações: instruções da gravação do microfone, figura do canto e
// atalho para a pasta das gravações.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/audio_recording_help.dart';
import 'package:zywny_comum/ui/theme.dart';

Widget _app(Future<bool> Function() open) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: SingleChildScrollView(child: AudioRecordingHelp(open: open)),
  ),
);

void main() {
  testWidgets('explica o gesto e mostra a figura do canto', (tester) async {
    await tester.pumpWidget(_app(() async => true));
    expect(find.textContaining('canto inferior esquerdo'), findsOneWidget);
    expect(find.textContaining('1 segundo'), findsOneWidget);
    expect(find.textContaining('160 kbps'), findsOneWidget);
    expect(find.byType(AudioCornerFigure), findsOneWidget);
  });

  testWidgets('o atalho abre a pasta', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_app(() async => ++opened > 0));
    await tester.tap(find.text('Abrir a pasta das gravações'));
    await tester.pump();
    expect(opened, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('se não abre, avisa onde procurar', (tester) async {
    await tester.pumpWidget(_app(() async => false));
    await tester.tap(find.text('Abrir a pasta das gravações'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Não consegui abrir a pasta'), findsOneWidget);
  });
}

// U03 — botão "Ouvir o trecho" da barra lateral e o aviso de teclado.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/ui/phone_chrome.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

PhoneRail _rail({VoidCallback? onListen, bool listening = false}) => PhoneRail(
  playing: false,
  onPlayPause: () {},
  measure: 5,
  totalMeasures: 56,
  tempoPercent: 100,
  handLabel: 'Ambas',
  onOptions: () {},
  onListen: onListen,
  listening: listening,
);

void main() {
  group('PhoneRail — ouvir o trecho', () {
    for (final size in const [Size(844, 390), Size(640, 360)]) {
      testWidgets(
        'na trilha tem o botão e chama o retorno em ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var taps = 0;
          await tester.pumpWidget(
            _app(
              Align(
                alignment: Alignment.centerRight,
                child: _rail(onListen: () => taps++),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Ouvir o trecho'));
          expect(taps, 1);
        },
      );
    }

    testWidgets('fora da trilha não existe', (tester) async {
      await tester.pumpWidget(_app(_rail()));
      expect(find.byTooltip('Ouvir o trecho'), findsNothing);
    });

    testWidgets('ouvindo vira "Parar de ouvir"', (tester) async {
      await tester.pumpWidget(_app(_rail(onListen: () {}, listening: true)));
      expect(find.byTooltip('Parar de ouvir'), findsOneWidget);
    });
  });

  testWidgets('aviso de teclado aparece e some com a conexão', (tester) async {
    final connected = ValueNotifier<bool>(false);
    var taps = 0;
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: connected,
          builder: (context, on, _) =>
              on ? const SizedBox() : PhoneKeyboardNotice(onTap: () => taps++),
        ),
      ),
    );
    expect(find.text('Conecte o teclado para praticar'), findsOneWidget);
    await tester.tap(find.byType(PhoneKeyboardNotice));
    expect(taps, 1);
    connected.value = true;
    await tester.pump();
    expect(find.text('Conecte o teclado para praticar'), findsNothing);
  });

  group('PhoneSoundButton', () {
    for (final on in [true, false]) {
      testWidgets('som ${on ? 'ligado' : 'desligado'}', (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _app(
            PhoneTitleBar(
              number: 5,
              title: 'Hino',
              onBack: () {},
              trailing: [
                PhoneSoundButton(
                  on: on,
                  tooltip: on ? 'Som ligado' : 'Som desligado',
                  onPressed: () => taps++,
                ),
              ],
            ),
          ),
        );
        expect(
          find.byIcon(on ? Icons.volume_up : Icons.volume_off),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip(on ? 'Som ligado' : 'Som desligado'));
        expect(taps, 1);
      });
    }

    testWidgets('desabilitado sem retorno', (tester) async {
      await tester.pumpWidget(
        _app(
          const PhoneSoundButton(
            on: true,
            tooltip: 'Som ligado',
            onPressed: null,
          ),
        ),
      );
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    });
  });
}

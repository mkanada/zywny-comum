import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/settings/color_picker.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Color initial = const Color(0xFF1E88E5),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Color? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showColorPicker(
                  context,
                  title: 'Treino: nota em espera',
                  initial: initial,
                  defaultColor: const Color(0xFF2E7D32),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    _result = () => result;
  }

  test('colorHex e a paleta', () {
    expect(colorHex(const Color(0xFF00838F)), '#00838F');
    expect(kColorPalette.toSet(), hasLength(kColorPalette.length));
    expect(kColorPalette.length, greaterThanOrEqualTo(40));
  });

  testWidgets('paleta: tocar numa cor e aplicar devolve a cor', (tester) async {
    await open(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Material && w.color == kColorPalette[10],
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(_result(), kColorPalette[10]);
  });

  testWidgets('código digitado vale; cancelar não devolve nada', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'ad1457');
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(_result(), const Color(0xFFAD1457));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(_result(), isNull);
  });

  testWidgets('"Padrão" repõe a cor padrão; o ajuste fino muda a cor', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Padrão'));
    await tester.pump();
    expect(find.text('2E7D32'), findsOneWidget);

    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pump();
    expect(find.text('2E7D32'), findsNothing);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(_result(), isNot(const Color(0xFF2E7D32)));
    expect(_result(), isNotNull);
  });

  testWidgets('celular deitado: cabe sem estourar', (tester) async {
    await open(tester, size: const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.text('Matiz'), findsOneWidget);
    expect(find.text('Aplicar'), findsOneWidget);
  });
}

Color? Function() _result = () => null;

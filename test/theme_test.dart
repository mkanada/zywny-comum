// U18 — o tema é o do app, não o que o Material deriva da semente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/ui/theme.dart';

void main() {
  test('o primário é o azul do app e as superfícies são as do app', () {
    final scheme = buildAppTheme().colorScheme;
    expect(scheme.primary, kAccent);
    expect(scheme.onPrimary, Colors.white);
    expect(scheme.surface, kSurface);
    expect(scheme.error, kBadColor);
    expect(scheme.outline, kBorder);
    expect(scheme.primaryContainer, kAccentSoftBg);
  });

  testWidgets('diálogo branco e botão principal azul', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Titulo'),
                actions: [
                  FilledButton(onPressed: () {}, child: const Text('Ok')),
                ],
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(dialog.color, kSurface);
    final button = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(button.color, kAccent);
  });
}

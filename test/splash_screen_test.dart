import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_clock/zywny_clock.dart';
import 'package:zywny_comum/app/splash_screen.dart';

void main() {
  testWidgets('splash cobre o app e some sozinha', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // O tempo da splash é o do relógio dado (CT05c): só anda quando o teste manda.
    final relogio = ManualClock(DateTime(2026, 11, 25, 10));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SplashOverlay(clock: relogio, child: const Text('app')),
      ),
    );
    expect(
      find.text('Todo grande pianista começou na primeira tecla.'),
      findsOneWidget,
    );
    expect(find.text('VARSÓVIA · 1816'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );

    relogio.advance(const Duration(milliseconds: 1900));
    // O aviso do cubit chega por um Stream (uma microtarefa): um quadro para
    // ele entrar no estado, outro para a árvore refazer o desenho.
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.pumpAndSettle();
  });
}

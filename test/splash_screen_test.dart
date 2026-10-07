import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/app/splash_screen.dart';

void main() {
  testWidgets('splash cobre o app e some sozinha', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SplashOverlay(child: Text('app')),
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

    await tester.pump(const Duration(milliseconds: 1900));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.pumpAndSettle();
  });
}

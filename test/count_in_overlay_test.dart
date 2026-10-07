import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/metronome.dart';
import 'package:zywny/practice/count_in_overlay.dart';

void main() {
  Widget host({required bool active, required CountInTick? Function() read}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 500,
            child: CountInOverlay(active: active, read: read),
          ),
        ),
      );

  double opacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byType(Opacity)).opacity;

  testWidgets('mostra o tempo que falta e esmaece até o próximo', (
    tester,
  ) async {
    CountInTick? tick = (remaining: 4, progress: 0.0);
    await tester.pumpWidget(host(active: true, read: () => tick));
    expect(find.text('4'), findsOneWidget);
    expect(opacity(tester), 1);
    // Nítido no clique: sem desfoque nem crescimento.
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.widget<Text>(find.text('4')).style!.color, kCountInColor);

    tick = (remaining: 4, progress: 0.75);
    await tester.pump(const Duration(milliseconds: 16));
    expect(opacity(tester), closeTo(countInOpacityAt(0.75), 1e-9));
    expect(opacity(tester), lessThan(0.5));
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
      tester.getSize(find.byType(ImageFiltered)),
      const Size(800, 500),
      reason: 'o desfoque cobre a caixa toda, senão a borda é cortada',
    );

    tick = (remaining: 3, progress: 0.0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('3'), findsOneWidget);
    expect(opacity(tester), 1);

    // Acabou a contagem: nada por cima da partitura.
    tick = null;
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('parado não consulta a contagem nem desenha', (tester) async {
    var reads = 0;
    CountInTick? read() {
      reads++;
      return (remaining: 2, progress: 0.5);
    }

    await tester.pumpWidget(host(active: false, read: read));
    await tester.pump(const Duration(milliseconds: 16));
    expect(reads, 0);
    expect(find.byType(Text), findsNothing);

    await tester.pumpWidget(host(active: true, read: read));
    expect(find.text('2'), findsOneWidget);

    // Pausa no meio da contagem: o número some na hora.
    await tester.pumpWidget(host(active: false, read: read));
    expect(find.byType(Text), findsNothing);
  });

  group('no celular (U09)', () {
    Widget phoneHost(CountInTick? Function() read) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 700,
          height: 300,
          child: CountInOverlay(phone: true, active: true, read: read),
        ),
      ),
    );

    testWidgets(
      'o número fica inteiro na metade direita e nunca passa de 0,5',
      (tester) async {
        CountInTick? tick = (remaining: 4, progress: 0.0);
        await tester.pumpWidget(phoneHost(() => tick));
        final box = tester.getRect(find.byType(CountInOverlay));
        final text = tester.getRect(find.text('4'));
        expect(text.left, greaterThan(box.center.dx));
        expect(text.right, lessThanOrEqualTo(box.right));
        expect(text.height, lessThanOrEqualTo(box.height * 0.45 + 1));
        expect(opacity(tester), closeTo(kCountInPhoneMaxOpacity, 1e-9));

        for (final p in [0.0, 0.3, 0.75, 1.0]) {
          tick = (remaining: 4, progress: p);
          await tester.pump(const Duration(milliseconds: 16));
          expect(opacity(tester), lessThanOrEqualTo(kCountInPhoneMaxOpacity));
        }
      },
    );

    testWidgets('sem desfoque nem escala', (tester) async {
      CountInTick? tick = (remaining: 3, progress: 0.8);
      await tester.pumpWidget(phoneHost(() => tick));
      expect(find.byType(ImageFiltered), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CountInOverlay),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });
  });
}

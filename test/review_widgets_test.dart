// A revisão do treino e os botões de página da partitura parada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/practice/review_bar.dart';
import 'package:zywny/ui/page_pager.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('PagePager', () {
    testWidgets('mostra a página e chama anterior/próxima', (tester) async {
      var back = 0, next = 0;
      await tester.pumpWidget(
        _host(
          PagePager(
            page: 1,
            pageCount: 4,
            onPrevious: () => back++,
            onNext: () => next++,
          ),
        ),
      );
      expect(find.text('2 / 4'), findsOneWidget);
      await tester.tap(find.byTooltip('Página anterior'));
      await tester.tap(find.byTooltip('Próxima página'));
      expect((back, next), (1, 1));
    });

    testWidgets('nas pontas o botão fica desabilitado', (tester) async {
      await tester.pumpWidget(
        _host(
          const PagePager(
            page: 0,
            pageCount: 2,
            onPrevious: null,
            onNext: null,
          ),
        ),
      );
      final back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(back.onPressed, isNull);
    });
  });

  group('ReviewBar', () {
    ReviewBar bar({
      int count = 3,
      bool reviewing = false,
      bool hasSides = true,
      VoidCallback? onReview,
      VoidCallback? onClose,
    }) => ReviewBar(
      count: count,
      reviewing: reviewing,
      hasSides: hasSides,
      onReview: onReview ?? () {},
      onPrevious: null,
      onNext: () {},
      onClose: onClose ?? () {},
    );

    testWidgets('depois do treino oferece Revisar', (tester) async {
      var reviewed = 0, closed = 0;
      await tester.pumpWidget(
        _host(bar(onReview: () => reviewed++, onClose: () => closed++)),
      );
      expect(find.text('3 notas para rever'), findsOneWidget);
      await tester.tap(find.text('Revisar'));
      await tester.tap(find.byTooltip('Dispensar'));
      expect((reviewed, closed), (1, 1));
    });

    testWidgets('uma nota só fica no singular', (tester) async {
      await tester.pumpWidget(_host(bar(count: 1)));
      expect(find.text('1 nota para rever'), findsOneWidget);
    });

    testWidgets('na revisão explica o lado e anda entre as páginas', (
      tester,
    ) async {
      await tester.pumpWidget(_host(bar(reviewing: true)));
      expect(find.text('Revisão · 3 notas para rever'), findsOneWidget);
      expect(find.textContaining('à esquerda da nota'), findsOneWidget);
      expect(find.text('Revisar'), findsNothing);
      final previous = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.keyboard_double_arrow_left),
      );
      expect(previous.onPressed, isNull);
    });

    testWidgets('sem nota fora do tempo (modo espera) não explica o lado', (
      tester,
    ) async {
      await tester.pumpWidget(_host(bar(reviewing: true, hasSides: false)));
      expect(find.textContaining('à esquerda da nota'), findsNothing);
    });
  });
}

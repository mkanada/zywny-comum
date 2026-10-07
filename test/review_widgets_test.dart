// Os botões de página da partitura parada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

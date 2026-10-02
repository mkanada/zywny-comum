// Desfoque da página revelada pela haste (`SweepCurtain.blur` ×
// `ScoreView.revealBlurSigma`): inteiro enquanto a haste entra e espera — o
// foco ainda é a página que toca —, caindo a zero nos primeiros 30% da saída.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('timeline: desfoque inteiro até a haste sair, depois cai com ela', () {
    final doc = _fixture('maple-leaf-rag.vsb');
    final tl = ScoreTimeline(doc);
    final bar = defaultBarWidth(doc);
    SweepCurtain? at(double ms) =>
        tl.curtainAt(ms, maxSweep: kDefaultMaxSweepDuration, barWidth: bar);

    // A primeira virada da peça, amostrada a cada 10 ms.
    final sweep = <SweepCurtain>[];
    for (var ms = 0.0; ms < tl.durationMs; ms += 10) {
      final c = at(ms);
      if (c != null) {
        sweep.add(c);
      } else if (sweep.isNotEmpty) {
        break;
      }
    }
    expect(sweep.length, greaterThan(20));

    final firstFade = sweep.indexWhere((c) => c.blur < 1);
    expect(firstFade, greaterThan(0), reason: 'entra e espera com tudo');
    // Dali em diante só cai, com a haste só avançando, até quase zero.
    for (var i = firstFade; i < sweep.length; i++) {
      expect(sweep[i].blur, lessThanOrEqualTo(sweep[i - 1].blur));
      expect(sweep[i].edgeX, greaterThan(sweep[i - 1].edgeX));
      expect(sweep[i].blur, inInclusiveRange(0, 1));
    }
    expect(sweep.last.blur, 0);
    // O desfoque some nos primeiros 30% da saída: dali em diante a página
    // nova já está nítida.
    final rest = sweep[firstFade - 1].edgeX;
    final end = sweepEndX(doc.pages[sweep.first.pageIndex], bar);
    double out(SweepCurtain c) => (c.edgeX - rest) / (end - rest);
    for (final c in sweep.skip(firstFade)) {
      expect(
        c.blur,
        closeTo((1 - out(c) / kRevealBlurClearAt).clamp(0.0, 1.0), 1e-6),
      );
    }
    expect(sweep.where((c) => out(c) >= kRevealBlurClearAt), isNotEmpty);
    expect(sweep.any((c) => c.blur > 0 && c.blur < 1), isTrue);
  });

  testWidgets('vista: a página de trás é desfocada na medida do blur', (
    tester,
  ) async {
    final doc = _fixture('maple-leaf-rag.vsb');
    final controller = ScoreController(document: doc);
    final curtain = ValueNotifier<SweepCurtain?>(null);
    final midX = sweepEndX(doc.pages[0], defaultBarWidth(doc)) / 2;

    Future<void> pump({required double sigma}) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: ScoreView(
              document: doc,
              controller: controller,
              curtain: curtain,
              revealBlurSigma: sigma,
            ),
          ),
        ),
      ),
    );

    try {
      await pump(sigma: 200);
      // Repouso: nada de filtro na árvore.
      expect(find.byType(ImageFiltered), findsNothing);

      curtain.value = SweepCurtain(pageIndex: 0, edgeX: midX, blur: 1);
      await tester.pump();
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isTrue,
      );

      curtain.value = SweepCurtain(pageIndex: 0, edgeX: midX);
      await tester.pump();
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isFalse,
      );

      // Sem `revealBlurSigma` a árvore é a de sempre, com qualquer blur.
      curtain.value = SweepCurtain(pageIndex: 0, edgeX: midX, blur: 1);
      await pump(sigma: 0);
      expect(find.byType(ImageFiltered), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.clearAll();
      controller.dispose();
      curtain.dispose();
    }
  });
}

// Regra da haste generalizada aos saltos de repetição (E03b, D-SALTO = (a)).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/sweep_rule.dart';

const _maxSweep = Duration(seconds: 1);
const _bar = 50.0;

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

void main() {
  late VsbDocument mapleLeafRag;
  late ScoreTimeline tl;

  setUpAll(() {
    // ScoreController usa um Ticker (highlightAll com release) mesmo no
    // teste de reprodução completa abaixo, que não é testWidgets.
    TestWidgetsFlutterBinding.ensureInitialized();
    mapleLeafRag = _fixture('maple-leaf-rag.vsb');
    tl = ScoreTimeline(mapleLeafRag);
  });

  SweepCurtain? at(double ms) =>
      tl.curtainAt(ms, maxSweep: _maxSweep, barWidth: _bar);

  // P01c: os padrões do bridge (D-VSB-PADRAO) cabem mais compassos por
  // página, então a paginação da Maple Leaf Rag mudou (o total de páginas
  // continua 3, mas os pontos de quebra andaram). O único salto que ainda
  // muda de página é este, da última página (2) para a anterior (1).
  //
  // P04a: `jn8k16x` não é o 1º compasso da página normal 1 (ver a tabela
  // "Saltos e pontos de chegada" do README), então é ponto de chegada de
  // alternativa (P02b) — a sequência 6 de `alternates.json` começa nele. Com
  // `useAlternates: true` (padrão), a regra de P00 escolhe a página 0 dela
  // no lugar da página normal 1 (`MeasureInfo.page` continua sendo 1,
  // D-ALT-INDICE; é `.view`/`SweepCurtain.target` que muda).
  group('salto 153900ms: compasso z1m4pqeg (última página, 2) -> jn8k16x '
      '(alternativa 6, página 0)', () {
    test(
      'entrada, estacionada e conclusão com target = PageRef(0, sequence: 6) '
      '(critério 1)',
      () {
        final i = tl.measures.indexWhere((m) => m.startMs == 153900);
        final m = tl.measures[i - 1]; // última ocorrência antes do salto
        final next = tl.measures[i]; // destino, passagem 2
        expect(m.page, 2);
        expect(next.page, 1); // página normal do compasso, inalterada
        expect(next.view, const PageRef(0, sequence: 6));
        expect(m.page, mapleLeafRag.pages.length - 1);
        final d = (m.endMs - m.startMs) / 4;
        final endX = sweepEndX(mapleLeafRag.pages[2], _bar);
        final x = mapleLeafRag.geometry.elementOf(m.id)!.bbox.left;

        // Antes da entrada: repouso.
        expect(at(m.startMs - 1.0), isNull);
        // Entrada: 0 -> x.
        final entering = at(m.startMs + d / 2)!;
        expect(entering.pageIndex, 2);
        expect(entering.targetPageIndex, 0);
        expect(entering.targetSequence, 6);
        expect(entering.edgeX, closeTo(x / 2, 1e-6));
        // A conclusão começa antes do fim de M (ver a regra no cabeçalho de
        // score_timeline.dart): a página de destino tem de estar pronta na
        // última nota ou pausa dele.
        final nextRight = mapleLeafRag
            .geometryOf(6)
            .elementOf(next.id)!
            .bbox
            .right;
        final l = lastEventMs(mapleLeafRag, m);
        final c = concStart(
          m: m,
          d: d,
          lastMs: l,
          fromX: x,
          endX: endX,
          revealX: nextRight + _bar,
        );
        expect(c, lessThan(next.startMs));
        // Estacionada em x.
        final parked = at((m.startMs + d + c) / 2)!;
        expect(parked.edgeX, closeTo(x, 1e-6));
        expect(parked.targetPageIndex, 0);
        expect(parked.targetSequence, 6);
        // Conclusão: x -> fim.
        final concluding = at(c + d / 2)!;
        expect(concluding.edgeX, closeTo(x + (endX - x) / 2, 1e-6));
        // Na última nota ou pausa a página de destino já está nítida.
        if (c > m.startMs + d) {
          expect(at(l)!.blur, closeTo(0, 1e-9));
          expect(at(l)!.edgeX, greaterThanOrEqualTo(nextRight + _bar - 1e-6));
        }
        // Repouso na alternativa, depois da conclusão — ainda dentro de M;
        // a página normal (D-ALT-INDICE) continua sendo a 1.
        expect(at(c + d), isNull);
        expect(tl.restPageAt(next.startMs + d), 1);
        const alternativa = PageRef(0, sequence: 6);
        expect(tl.restViewAt(next.startMs + d), alternativa);
        expect(
          tl.shownViewAt(c + d, maxSweep: _maxSweep, barWidth: _bar),
          alternativa,
        );
        expect(
          tl.shownViewAt(c + d - 1, maxSweep: _maxSweep, barWidth: _bar),
          m.view,
        );
      },
    );
  });

  group('sem haste nos saltos de mesma página (fora de escopo)', () {
    test('mdf3uku -> q1t6l0ej (passagem 2, mesma página): repouso o tempo '
        'todo', () {
      final i = tl.measures.indexWhere((m) => m.startMs == 19500);
      final m = tl.measures[i - 1];
      final next = tl.measures[i];
      expect(m.page, next.page);
      for (var ms = m.startMs - 500; ms <= next.startMs + 500; ms += 50) {
        expect(at(ms.toDouble()), isNull, reason: 'ms=$ms');
      }
    });
  });

  test(
    'ScorePlayer toca a Maple Leaf Rag do início ao fim a 4x sem exceção',
    () {
      final controller = ScoreController(document: mapleLeafRag);
      final player = ScorePlayer(
        document: mapleLeafRag,
        controller: controller,
      );
      try {
        // Sem tester.pump (a 4x é só para simular passos maiores que uma
        // entrada de timemap, cruzando vários saltos de uma vez): avança
        // manualmente até o fim, sem usar play()/isPlaying (que dependem
        // de um Ticker real, movido por frames reais — fora do escopo
        // deste teste, que só quer garantir que nada explode).
        var steps = 0;
        while (player.position < player.duration && steps < 20000) {
          player.advance(const Duration(milliseconds: 200)); // 50ms * 4x
          steps++;
        }
        expect(player.position, player.duration);
      } finally {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      }
    },
  );
}

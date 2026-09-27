// Portão da fase E (E05): as 10 peças do corpus e as 13 partituras de E01a
// tocam na ordem que um músico tocaria, ponta a ponta (partitura → .vsb →
// ScoreTimeline), e as peças com repetição de verdade tocam do início ao
// fim sem exceção.
//
// Compara com o .esperado de cada peça — que compara o caminho do
// `repeat-order.py` (E01a, lê o timemap) com o caminho do Dart
// (ScoreTimeline.measures, que resolve ids expandidos e monta ocorrências,
// E02a/E02b): são dois caminhos independentes, e um erro de resolução de id
// só aparece no Dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _fixturesDir = 'test/fixtures/repeticoes';
const _repeticoesDir = '../corpus/repeticoes';

/// As 13 partituras mínimas de E01a: nome do fixture -> arquivo `.esperado`
/// (ao lado da partitura em `corpus/repeticoes/`).
const _minimalScores = {
  'r01-ritornelo': 'r01-ritornelo.musicxml.esperado',
  'r02-ritornelo': 'r02-ritornelo.mei.esperado',
  'r03-casas': 'r03-casas.musicxml.esperado',
  'r04-casas': 'r04-casas.mei.esperado',
  'r05-casa-1-sozinha': 'r05-casa-1-sozinha.musicxml.esperado',
  'r06-salto-de-pagina': 'r06-salto-de-pagina.musicxml.esperado',
  'r07-salto-de-pagina': 'r07-salto-de-pagina.mei.esperado',
  'r08-dc-al-fine': 'r08-dc-al-fine.musicxml.esperado',
  'r09-ds-al-coda': 'r09-ds-al-coda.musicxml.esperado',
  'r10-tres-vezes': 'r10-tres-vezes.musicxml.esperado',
  'r11-varias-sections': 'r11-varias-sections.mei.esperado',
  'r12-expansion-codificada': 'r12-expansion-codificada.mei.esperado',
  'r13-um-compasso': 'r13-um-compasso.musicxml.esperado',
};

/// As 10 peças do corpus: nome do fixture -> arquivo `.esperado` (em
/// `corpus/repeticoes/esperado/`).
const _corpusPieces = {
  'Erik_Satie_-_Gymnopedie_No.1': 'Erik_Satie_-_Gymnopedie_No.1.esperado',
  'Maple_Leaf_Rag_Scott_Joplin': 'Maple_Leaf_Rag_Scott_Joplin.esperado',
  'Chopin_-_Nocturne_Op._9_No._1': 'Chopin_-_Nocturne_Op._9_No._1.esperado',
  'Clair_de_Lune__Debussy': 'Clair_de_Lune__Debussy.esperado',
  'Prelude_I_in_C_major_BWV_846_-_Well_Tempered_Clavier_First_Book': 'Prelude_I_in_C_major_BWV_846_-_Well_Tempered_Clavier_First_Book.esperado',
  'Chopin_Etude_Op10_No9': 'Chopin_Etude_Op10_No9.esperado',
  'Chopin_Mazurka_Op6_No1': 'Chopin_Mazurka_Op6_No1.esperado',
  'Grieg_Butterfly_Op43_No1': 'Grieg_Butterfly_Op43_No1.esperado',
  'Grieg_Little_bird_Op43_No4': 'Grieg_Little_bird_Op43_No4.esperado',
  'Scarlatti_Sonata_in_C-major': 'Scarlatti_Sonata_in_C-major.esperado',
};

/// Peças com repetição de verdade (sequência com mais de um bloco):
/// exercitadas também com um `ScorePlayer` do início ao fim (critério 2).
const _piecesWithRepeats = [
  'Erik_Satie_-_Gymnopedie_No.1',
  'Maple_Leaf_Rag_Scott_Joplin',
  'Chopin_Mazurka_Op6_No1',
  'Grieg_Butterfly_Op43_No1',
  'Grieg_Little_bird_Op43_No4',
  'Scarlatti_Sonata_in_C-major',
];

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('$_fixturesDir/$name.vsb').readAsBytesSync());

/// Ids de compasso da cena, em ordem de documento (1-based).
List<String> _measureOrder(VsbDocument doc) {
  final order = <String>[];
  void walk(SceneNode n) {
    if (n.className == 'measure' && n.id != null) {
      order.add(n.id!);
    }
    for (final c in n.children) {
      if (c is SceneNode) walk(c);
    }
  }

  for (final p in doc.pages) {
    walk(p.root);
  }
  return order;
}

/// A sequência de execução de [doc] em blocos (`1-4 1-4 5-6`), no mesmo
/// formato dos `.esperado` de E01a: agrupa ocorrências consecutivas cujo
/// compasso é o seguinte, na ordem de documento, e cuja passagem não muda.
String _blockSequence(VsbDocument doc) {
  final order = _measureOrder(doc);
  final docPosition = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i + 1,
  };
  final tl = ScoreTimeline(doc);
  final numbers = [for (final m in tl.measures) docPosition[m.id]!];
  final passes = [for (final m in tl.measures) m.pass];

  final blocks = <String>[];
  var i = 0;
  while (i < numbers.length) {
    var j = i;
    while (j + 1 < numbers.length &&
        numbers[j + 1] == numbers[j] + 1 &&
        passes[j + 1] == passes[j]) {
      j++;
    }
    blocks.add(
      numbers[i] == numbers[j]
          ? '${numbers[i]}'
          : '${numbers[i]}-${numbers[j]}',
    );
    i = j + 1;
  }
  return blocks.join(' ');
}

void main() {
  setUpAll(() {
    // ScoreController usa um Ticker (highlightAll com release) mesmo nos
    // testes de reprodução completa abaixo, que não são testWidgets.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('sequência de execução == .esperado (critério 1)', () {
    for (final entry in {..._minimalScores, ..._corpusPieces}.entries) {
      final esperadoDir = _minimalScores.containsKey(entry.key)
          ? _repeticoesDir
          : '$_repeticoesDir/esperado';
      test(entry.key, () {
        final doc = _fixture(entry.key);
        final expected = File('$esperadoDir/${entry.value}')
            .readAsStringSync()
            .trim();
        expect(_blockSequence(doc), expected);
      });
    }
  });

  group('ScorePlayer toca do início ao fim sem exceção (critério 2)', () {
    for (final name in _piecesWithRepeats) {
      testWidgets(name, (tester) async {
        final doc = _fixture(name);
        final controller = ScoreController(document: doc);
        final player = ScorePlayer(document: doc, controller: controller);
        try {
          player.play();
          player.speed = 4.0;
          var frames = 0;
          while (player.isPlaying && frames < 5000) {
            await tester.pump(const Duration(milliseconds: 100));
            frames++;
          }
          expect(player.isPlaying, isFalse, reason: name);
          expect(player.position, player.duration, reason: name);
          // Deixa o release de qualquer destaque em curso terminar (o
          // relógio do ScoreController é o dele, não o do player).
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            controller.highlightedCount,
            0,
            reason: '$name: nada deveria continuar aceso no fim',
          );
          // Página final correta: a posição, no fim, resolve para a página
          // do último compasso executado (sem ScoreView montada, é isso que
          // dá para verificar sem um teste de widget).
          final tl = player.timeline;
          expect(
            tl.restPageAt(player.position.inMilliseconds.toDouble()),
            tl.measures.last.page,
            reason: name,
          );
        } finally {
          controller.clearAll();
          player.dispose();
          controller.dispose();
        }
      });
    }
  });
}

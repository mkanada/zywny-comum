// Ids expandidos do timemap (`-rend<N>`) → nó da cena (E02a).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/fake_doc.dart';
import 'support/render_helpers.dart';

void main() {
  group('IdExpansion.sceneIdOf/passOf (regra do sufixo, critério 1)', () {
    final expansion = IdExpansion({'x', 'x-rend2'});

    test('id da cena, sem sufixo -> ele mesmo, passagem 1', () {
      expect(expansion.sceneIdOf('x'), 'x');
      expect(expansion.passOf('x'), 1);
    });

    test('x-rend2 com x na cena -> x, passagem 2', () {
      final e = IdExpansion({'x'});
      expect(e.sceneIdOf('x-rend2'), 'x');
      expect(e.passOf('x-rend2'), 2);
    });

    test('x-rend3 -> x, passagem 3', () {
      final e = IdExpansion({'x'});
      expect(e.sceneIdOf('x-rend3'), 'x');
      expect(e.passOf('x-rend3'), 3);
    });

    test(
      'x-rend2 presente na própria cena -> ele mesmo, nunca tira o sufixo',
      () {
        expect(expansion.sceneIdOf('x-rend2'), 'x-rend2');
        expect(expansion.passOf('x-rend2'), 1);
      },
    );

    test('base ausente da cena -> null', () {
      final e = IdExpansion({'x'});
      expect(e.sceneIdOf('nao-existe-rend2'), isNull);
    });

    test('sufixo não numérico (rendezvous) -> null', () {
      final e = IdExpansion({'abc'});
      expect(e.sceneIdOf('abc-rendezvous'), isNull);
    });
  });

  group('VsbDocument.sceneIdOf/passOf', () {
    late VsbDocument doc;

    setUp(() {
      doc = fakeDocument([
        [
          FakeMeasure('m1', 0, [FakeNote('m1n1', 10)]),
        ],
      ], const []);
    });

    test('delega para IdExpansion sobre todos os ids de todas as páginas', () {
      expect(doc.sceneIdOf('m1'), 'm1');
      expect(doc.sceneIdOf('m1n1-rend2'), 'm1n1');
      expect(doc.passOf('m1n1-rend2'), 2);
      expect(doc.sceneIdOf('nada-rend2'), isNull);
    });
  });

  group('animatableIdsFromTimemap com document (critério 5)', () {
    test('id que só existe como -rend2 no timemap torna a base dinâmica', () {
      final doc = fakeDocument([
        [
          FakeMeasure('m1', 0, [FakeNote('x', 10)]),
        ],
      ], const []);
      final timemap = [
        const TimemapEntry(
          tstamp: 0,
          on: ['x-rend2'],
          off: [],
          restsOn: [],
          restsOff: [],
        ),
      ];
      final withoutDoc = animatableIdsFromTimemap(timemap);
      expect(withoutDoc, {'x-rend2'});
      expect(withoutDoc, isNot(contains('x')));

      final withDoc = animatableIdsFromTimemap(timemap, document: doc);
      expect(withDoc, {'x'});

      final page = doc.pages[0];
      final segmentsWithout = segmentPage(page, withoutDoc);
      final segmentsWith = segmentPage(page, withDoc);
      // sem o documento, 'x-rend2' não existe na página: nenhum segmento
      // dinâmico. Com o documento, a nota 'x' vira dinâmica.
      expect(segmentsWithout.whereType<DynamicSegment>(), isEmpty);
      expect(segmentsWith.whereType<DynamicSegment>(), isNotEmpty);
    });

    final files = corpusFiles();
    if (files.isEmpty) {
      test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
    } else {
      test('conjunto de nós dinâmicos por página é idêntico ao de antes nas '
          'peças do corpus (nenhuma base de -rendN falta no timemap sem '
          'sufixo, E01a)', () {
        for (final f in files) {
          final doc = VsbDocument.fromBytes(f.readAsBytesSync());
          final without = animatableIdsFromTimemap(doc.timemap);
          final with_ = animatableIdsFromTimemap(doc.timemap, document: doc);
          for (final page in doc.pages) {
            final pageIds = page.byId.keys.toSet();
            final dynWithout = without.intersection(pageIds);
            final dynWith = with_.intersection(pageIds);
            expect(
              dynWith,
              dynWithout,
              reason: '${f.path} página ${page.index}',
            );
          }
        }
      });
    }
  });

  group('ScoreGeometry resolve ids expandidos (critério 6)', () {
    // scrollToId('x-rend2') é testado em score_view_test.dart, que já monta
    // o widget necessário (ScoreViewController precisa de um ScoreView vivo).
    test('rectForId(x-rend2) == rectForId(x)', () {
      final doc = fakeDocument([
        [
          FakeMeasure('m1', 0, [FakeNote('x', 10)]),
        ],
      ], const []);
      final geometry = doc.geometry;
      final direct = geometry.rectForId('x');
      final expanded = geometry.rectForId('x-rend2');
      expect(expanded, isNotNull);
      expect(expanded, direct);
      expect(geometry.pageOf('x-rend2'), geometry.pageOf('x'));
      expect(geometry.elementOf('x-rend2')!.id, 'x');
    });
  });

  group('ScoreController resolve ids expandidos', () {
    test('setColor/highlight/colorOf em x-rend2 afetam o nó x', () {
      final doc = fakeDocument([
        [
          FakeMeasure('m1', 0, [FakeNote('x', 10)]),
        ],
      ], const []);
      final controller = ScoreController(document: doc);
      addTearDown(controller.dispose);

      controller.setColor('x-rend2', const ui.Color(0xFF00FF00));
      expect(controller.colorOf('x'), const ui.Color(0xFF00FF00));
      expect(controller.colorOf('x-rend2'), const ui.Color(0xFF00FF00));

      controller.clearColor('x-rend2');
      expect(controller.colorOf('x'), isNull);
    });
  });
}

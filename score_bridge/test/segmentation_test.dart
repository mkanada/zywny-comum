// Testes de A01a — segmentação da página por ordem de documento.
//
// Sem `Canvas` real: a segmentação é só lógica. O `RecordingCanvas` entra só
// como oráculo da transformação acumulada (ele compõe `save/translate/rotate`
// na mesma ordem do `Canvas`, sem compartilhar código com `Transform2D`).
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/recording_canvas.dart';

const _black = Color(0xFF000000);
const _red = Color(0xFFFF0000);

SceneNode _node({
  String? id,
  String? color,
  bool hidden = false,
  SceneRotate? rotate,
  List<SceneChild> children = const [],
}) {
  return SceneNode(
    id: id,
    className: 'g',
    color: color,
    hidden: hidden,
    rotate: rotate,
    children: children,
  );
}

/// Folha identificável pelo `x` (a identidade do objeto já basta, o `x` só
/// ajuda a ler falhas).
SceneRect _leaf(double x) {
  return SceneRect(
    x: x,
    y: 0,
    w: 10,
    h: 10,
    rx: 0,
    fill: ScenePaint.inherit,
    fillOpacity: 1.0,
    stroke: ScenePaint.none,
    strokeWidth: null,
    strokeOpacity: 1.0,
    lineCap: SceneLineCap.defaultCap,
    lineJoin: SceneLineJoin.defaultJoin,
    dash: null,
  );
}

ScenePage _page(SceneNode root) {
  return ScenePage(
    index: 0,
    width: 1000,
    height: 1000,
    contentHeight: 1000,
    viewBoxFactor: 10.0,
    viewBox: const Rect.fromLTRB(0, 0, 1000, 1000),
    baseWidth: 1000,
    baseHeight: 1000,
    userScaleX: 1.0,
    userScaleY: 1.0,
    widthPx: 1000,
    heightPx: 1000,
    fit: const PageFit(scale: 1.0, tx: 0.0, ty: 0.0),
    origin: Offset.zero,
    root: root,
    elements: const [],
    byId: const {},
  );
}

/// Referência independente: o percurso original, escrito à mão. Devolve, em
/// ordem de documento, as folhas visíveis e os nós dinâmicos (inteiros).
List<SceneChild> _expectedOrder(SceneNode node, Set<String> dynamicIds) {
  if (node.hidden) {
    return const [];
  }
  return [
    for (final child in node.children)
      if (child is SceneNode)
        if (child.id != null && dynamicIds.contains(child.id))
          ...(child.hidden ? const <SceneChild>[] : [child])
        else
          ..._expectedOrder(child, dynamicIds)
      else
        child,
  ];
}

/// Todos os itens de todos os segmentos, na ordem em que aparecem.
List<SceneChild> _flatten(List<PageSegment> segments) {
  return [
    for (final segment in segments)
      switch (segment) {
        StaticSegment() => [for (final item in segment.items) item.child],
        DynamicSegment() => segment.nodes,
      }.cast<SceneChild>(),
  ].expand((list) => list).toList();
}

int _drawableLeafCount(SceneNode node) {
  if (node.hidden) {
    return 0;
  }
  var total = 0;
  for (final child in node.children) {
    total += child is SceneNode ? _drawableLeafCount(child) : 1;
  }
  return total;
}

void main() {
  group('ordem e fusão', () {
    // 10 elementos "de página": 3 dinâmicos (n1, n2, n3), 7 estáticos.
    late SceneNode n1, n2, n3;
    late List<SceneRect> leaves;
    late ScenePage page;

    setUp(() {
      leaves = [for (var i = 0; i < 7; i++) _leaf(i * 20.0)];
      n1 = _node(id: 'n1', children: [_leaf(500), _leaf(510)]);
      n2 = _node(id: 'n2', children: [_leaf(520)]);
      n3 = _node(id: 'n3', children: [_leaf(530), _leaf(540)]);
      page = _page(
        _node(
          children: [
            leaves[0],
            _node(children: [leaves[1], n1, leaves[2]]), // n1 dentro de grupo
            leaves[3],
            _node(
              children: [
                _node(children: [n2]),
              ],
            ), // n2 fundo, sozinho
            _node(children: [leaves[4], leaves[5]]),
            n3,
            leaves[6],
          ],
        ),
      );
    });

    test(
      'critério 2: concatenar os segmentos reproduz o percurso original',
      () {
        const ids = {'n1', 'n2', 'n3'};
        final segments = segmentPage(page, ids);

        final expected = _expectedOrder(page.root, ids);
        // 7 folhas estáticas + 3 nós dinâmicos.
        expect(expected, hasLength(10));
        expect(_flatten(segments), orderedEquals(expected));
        // A ordem esperada tem mesmo os dinâmicos onde a árvore os põe:
        // l0 l1 [n1] l2 l3 [n2] l4 l5 [n3] l6.
        expect(expected[2], same(n1));
        expect(expected[5], same(n2));
        expect(expected[8], same(n3));
      },
    );

    test('alterna estático e dinâmico, e nunca há segmento vazio', () {
      final segments = segmentPage(page, {'n1', 'n2', 'n3'});
      expect(segments.map((s) => s.runtimeType).toList(), [
        StaticSegment, // leaves[0], leaves[1]
        DynamicSegment, // n1
        StaticSegment, // leaves[2], leaves[3]
        DynamicSegment, // n2
        StaticSegment, // leaves[4], leaves[5]
        DynamicSegment, // n3
        StaticSegment, // leaves[6]
      ]);
      for (final segment in segments) {
        switch (segment) {
          case StaticSegment():
            expect(segment.items, isNotEmpty);
          case DynamicSegment():
            expect(segment.items, isNotEmpty);
        }
      }
    });

    test('critério 3: dois nós dinâmicos adjacentes viram um segmento', () {
      final adjacent = _page(_node(children: [_leaf(0), n1, n2, _leaf(1)]));
      final segments = segmentPage(adjacent, {'n1', 'n2'});

      expect(segments, hasLength(3));
      final dynamic = segments[1] as DynamicSegment;
      expect(dynamic.nodes, hasLength(2));
      expect(dynamic.nodes[0], same(n1));
      expect(dynamic.nodes[1], same(n2));
    });

    test(
      'dinâmicos em grupos irmãos, sem nada desenhado entre eles, se fundem',
      () {
        final page = _page(
          _node(
            children: [
              _node(children: [_leaf(0), n1]),
              _node(), // grupo vazio entre os dois: não desenha nada
              _node(hidden: true, children: [_leaf(99)]), // nem este
              _node(children: [n2, _leaf(1)]),
            ],
          ),
        );
        final segments = segmentPage(page, {'n1', 'n2'});

        expect(segments.map((s) => s.runtimeType).toList(), [
          StaticSegment,
          DynamicSegment,
          StaticSegment,
        ]);
        expect((segments[1] as DynamicSegment).nodes, [same(n1), same(n2)]);
      },
    );

    test('uma folha estática entre dois dinâmicos os separa', () {
      final page = _page(_node(children: [n1, _leaf(0), n2]));
      final segments = segmentPage(page, {'n1', 'n2'});
      expect(segments.map((s) => s.runtimeType).toList(), [
        DynamicSegment,
        StaticSegment,
        DynamicSegment,
      ]);
    });

    test('não desce num nó dinâmico procurando outro dentro', () {
      final inner = _node(id: 'inner', children: [_leaf(1)]);
      final outer = _node(id: 'outer', children: [_leaf(0), inner]);
      final segments = segmentPage(_page(_node(children: [outer])), {
        'outer',
        'inner',
      });
      expect(segments, hasLength(1));
      expect((segments.single as DynamicSegment).nodes, [same(outer)]);
    });
  });

  group('estado herdado', () {
    test('critério 4: a cor herdada vem dos ancestrais', () {
      final inRed = _leaf(1);
      final afterRed = _leaf(2);
      final page = _page(
        _node(
          children: [
            _leaf(0),
            _node(
              color: '#ff0000',
              children: [
                inRed,
                _node(children: [_leaf(3)]),
              ],
            ),
            afterRed,
          ],
        ),
      );
      final segment = segmentPage(page, {}).single as StaticSegment;
      final byChild = {for (final i in segment.items) i.child: i};

      expect(segment.items.first.inheritedColor, _black);
      expect(byChild[inRed]!.inheritedColor, _red);
      // Cor de grupo desce até as folhas mais fundas...
      expect(segment.items[2].inheritedColor, _red);
      // ...e não vaza para o irmão seguinte.
      expect(byChild[afterRed]!.inheritedColor, _black);
    });

    test('critério 4: a transformação vem do `rotate` do ancestral', () {
      final inside = _leaf(1);
      final outside = _leaf(2);
      final page = _page(
        _node(
          children: [
            _node(
              rotate: const SceneRotate(angle: 90, origin: Offset(100, 100)),
              children: [inside],
            ),
            outside,
          ],
        ),
      );
      final segment = segmentPage(page, {}).single as StaticSegment;
      final byChild = {for (final i in segment.items) i.child: i};

      expect(byChild[outside]!.transform, isNull);

      final t = byChild[inside]!.transform!;
      // 90° em torno de (100, 100), à mão: (110, 100) -> (100, 110) e a
      // origem é ponto fixo.
      final p = t.apply(const Offset(110, 100));
      expect(p.dx, closeTo(100, 1e-9));
      expect(p.dy, closeTo(110, 1e-9));
      final o = t.apply(const Offset(100, 100));
      expect(o.dx, closeTo(100, 1e-9));
      expect(o.dy, closeTo(100, 1e-9));
    });

    test('a transformação acumulada bate com a do Canvas (oráculo)', () {
      // Dois `rotate` aninhados, com ângulo e pivô diferentes.
      const outer = SceneRotate(angle: -30, origin: Offset(400, 250));
      const inner = SceneRotate(angle: 75, origin: Offset(120, 60));
      final leaf = _leaf(1);
      final page = _page(
        _node(
          children: [
            _node(
              rotate: outer,
              children: [
                _node(rotate: inner, children: [leaf]),
              ],
            ),
          ],
        ),
      );
      final item = (segmentPage(page, {}).single as StaticSegment).items.single;
      final transform = item.transform!;

      // Oráculo 1: as mesmas operações que o `ScenePainter` faz.
      final oracle = RecordingCanvas();
      for (final r in [outer, inner]) {
        oracle.save();
        oracle.translate(r.origin.dx, r.origin.dy);
        oracle.rotate(r.angle * 3.141592653589793 / 180.0);
        oracle.translate(-r.origin.dx, -r.origin.dy);
      }
      // Oráculo 2: a matriz 4x4 entregue a `Canvas.transform`.
      final viaMatrix = RecordingCanvas()..transform(transform.toMatrix4());

      for (final p in const [Offset(0, 0), Offset(37, -12), Offset(500, 900)]) {
        final expected = oracle.transformPoint(p.dx, p.dy);
        final got = transform.apply(p);
        expect(got.dx, closeTo(expected.dx, 1e-9), reason: '$p');
        expect(got.dy, closeTo(expected.dy, 1e-9), reason: '$p');
        final m = viaMatrix.transformPoint(p.dx, p.dy);
        expect(m.dx, closeTo(expected.dx, 1e-9), reason: 'matriz $p');
        expect(m.dy, closeTo(expected.dy, 1e-9), reason: 'matriz $p');
      }
    });

    test('nó dinâmico: estado herdado é o de antes dele, não o dele', () {
      final note = _node(
        id: 'n1',
        color: '#ff0000', // a cor própria vale dentro da nota, na pintura
        rotate: const SceneRotate(angle: 45, origin: Offset(10, 10)),
        children: [_leaf(0)],
      );
      final page = _page(
        _node(
          color: '#00ff00',
          rotate: const SceneRotate(angle: 90, origin: Offset(100, 100)),
          children: [note],
        ),
      );
      final item =
          (segmentPage(page, {'n1'}).single as DynamicSegment).items.single;

      expect(item.node, same(note));
      expect(item.inheritedColor, const Color(0xFF00FF00));
      // Só o `rotate` do ancestral: 90° em torno de (100, 100).
      final p = item.transform!.apply(const Offset(110, 100));
      expect(p.dx, closeTo(100, 1e-9));
      expect(p.dy, closeTo(110, 1e-9));
    });
  });

  group('robustez', () {
    test('critério 5: ids que não existem na página são ignorados', () {
      final page = _page(
        _node(
          children: [
            _leaf(0),
            _node(id: 'n1', children: [_leaf(1)]),
            _leaf(2),
          ],
        ),
      );
      final baseline = segmentPage(page, {'n1'});
      final withGhosts = segmentPage(page, {
        'n1',
        'n1-rend2', // como as repetições da Gymnopédie
        'n2-rend2',
        'nao-existe',
      });

      expect(withGhosts.map((s) => s.runtimeType).toList(), [
        StaticSegment,
        DynamicSegment,
        StaticSegment,
      ]);
      expect(_flatten(withGhosts), orderedEquals(_flatten(baseline)));
      for (final segment in withGhosts) {
        expect(switch (segment) {
          StaticSegment() => segment.items.length,
          DynamicSegment() => segment.items.length,
        }, greaterThan(0));
      }
    });

    test('só ids inexistentes: um único segmento estático', () {
      final page = _page(_node(children: [_leaf(0), _leaf(1)]));
      final segments = segmentPage(page, {'x-rend2', 'y-rend2'});
      expect(segments, hasLength(1));
      expect(segments.single, isA<StaticSegment>());
    });

    test('`hidden` some: subárvore oculta e nó dinâmico oculto', () {
      final hiddenNote = _node(id: 'n1', hidden: true, children: [_leaf(9)]);
      final page = _page(
        _node(
          children: [
            _leaf(0),
            _node(hidden: true, children: [_leaf(1), _leaf(2)]),
            hiddenNote,
            _leaf(3),
          ],
        ),
      );
      final segments = segmentPage(page, {'n1'});
      expect(segments, hasLength(1)); // sem dinâmico: o oculto não conta
      expect(
        (segments.single as StaticSegment).items.map(
          (i) => (i.child as SceneRect).x,
        ),
        [0, 3],
      );
    });

    test('página sem nada desenhável: nenhum segmento', () {
      final page = _page(_node(children: [_node(), _node(hidden: true)]));
      expect(segmentPage(page, {}), isEmpty);
    });

    test('a raiz pode ser dinâmica: a página inteira vira um segmento', () {
      final root = _node(id: 'root', children: [_leaf(0), _leaf(1)]);
      final segments = segmentPage(_page(root), {'root'});
      expect(segments, hasLength(1));
      expect((segments.single as DynamicSegment).nodes, [same(root)]);
    });
  });

  group('contagens', () {
    test('segmentCount e contagem por tipo', () {
      final page = _page(
        _node(
          children: [
            _leaf(0),
            _leaf(1),
            _node(id: 'a', children: [_leaf(2)]),
            _node(id: 'b', children: [_leaf(3)]),
            _leaf(4),
          ],
        ),
      );
      final segments = segmentPage(page, {'a', 'b'});
      expect(segments.segmentCount, 3);
      expect(segments.staticSegmentCount, 2);
      expect(segments.dynamicSegmentCount, 1);
      expect(segments.staticItemCount, 3);
      expect(segments.dynamicNodeCount, 2);
    });

    test('animatableIdsFromTimemap: on e off, sem pausas', () {
      const entry = TimemapEntry(
        tstamp: 0,
        on: ['a', 'b'],
        off: ['a', 'c'],
        restsOn: ['r1'],
        restsOff: ['r2'],
      );
      expect(animatableIdsFromTimemap([entry]), {'a', 'b', 'c'});
      expect(animatableIdsFromTimemap(null), isEmpty);
    });
  });

  group('no fixture do corpus (Gymnopédie)', () {
    late VsbDocument doc;

    setUpAll(() {
      doc = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
    });

    test('critério 7: sem ids animáveis, 1 segmento estático por página', () {
      for (final page in doc.pages) {
        final segments = segmentPage(page, const {});
        expect(segments, hasLength(1), reason: 'página ${page.index}');
        final segment = segments.single as StaticSegment;
        expect(segment.items.length, _drawableLeafCount(page.root));
        // Sem nenhum ancestral colorido ou rotacionado no fixture, tudo herda
        // o preto e a identidade.
        expect(segment.items.every((i) => i.transform == null), isTrue);
      }
    });

    test('ids do timemap: existem na página ou são ignorados, sem erro', () {
      final ids = animatableIdsFromTimemap(doc.timemap);
      expect(ids, isNotEmpty);
      for (final page in doc.pages) {
        final present = ids.where(page.byId.containsKey).toSet();
        // O timemap é da peça inteira: cada página só tem parte dos ids.
        expect(present.length, lessThan(ids.length), reason: 'p${page.index}');

        final segments = segmentPage(page, ids);
        expect(segments.dynamicNodeCount, present.length);
        expect(segments.segmentCount, greaterThan(1));
        // A concatenação reproduz o percurso original com os dinâmicos.
        expect(
          _flatten(segments),
          orderedEquals(_expectedOrder(page.root, ids)),
        );
        // Alternância estrita: nunca dois segmentos do mesmo tipo seguidos.
        for (var i = 1; i < segments.length; i++) {
          expect(
            segments[i].runtimeType,
            isNot(segments[i - 1].runtimeType),
            reason: 'p${page.index} segmento $i',
          );
        }
      }
    });
  });
}

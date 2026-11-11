// Faixa atrás das notas (T18 LP03): a conta dos retângulos (`scoreBandRects`)
// e a pintura na página (`ScorePageView` com `bands`). Usa o `satie.vsb` da
// nota fantasma: as notas de `tdowfwl` (uma pauta do sistema de baixo da
// página 0) e de `ufsr9k5` (a pauta de fá do mesmo sistema), e `orw55dt`, de
// outro sistema da página 0.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

const _doros = 'você';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  late VsbDocument doc;
  late ScenePage page;
  late ScoreGeometry geometry;

  setUp(() {
    doc = VsbDocument.fromBytes(
      File('test/fixtures/fantasma/satie.vsb').readAsBytesSync(),
    );
    page = doc.pages[0];
    geometry = doc.geometry;
  });

  /// Um id de nota que está na página 1 (o teste de página alheia).
  String noteOnPageOne() => doc.midi!.notes
      .map((n) => n.id)
      .firstWhere((id) => doc.geometry.elementOf(id)?.page == 1);

  List<ScoreBandRect> rectsOf(List<String> ids, {String? label}) =>
      scoreBandRects(page, 0, geometry, [ScoreBand(ids, label: label)]);

  test('duas colunas de uma pauta dão um retângulo com a conta da pauta', () {
    const ids = ['e11eog5', 'xej0b6o'];
    final rects = rectsOf(ids, label: _doros);
    expect(rects, hasLength(1));
    final r = rects.single;

    final staff = page.byId['tdowfwl']!.staffGeometry!;
    final space = 2 * staff.unit;
    final refs = ids.map((id) => geometry.elementOf(id)!.bbox).toList();
    // Cada nota dentro do retângulo, e ele mais largo que a nota maior.
    for (final b in refs) {
      expect(r.rect.left <= b.left && b.right <= r.rect.right, isTrue);
      expect(r.rect.top <= b.top && b.bottom <= r.rect.bottom, isTrue);
    }
    expect(
      r.rect.width,
      greaterThan(refs.map((b) => b.width).reduce((a, b) => a > b ? a : b)),
    );

    // Horizontal: da menor à maior nota, com `space` de folga de cada lado.
    final left = refs.map((b) => b.left).reduce((a, b) => a < b ? a : b);
    final right = refs.map((b) => b.right).reduce((a, b) => a > b ? a : b);
    expect(r.rect.left, left - space);
    expect(r.rect.right, right + space);
    // Vertical: a pauta inteira (com uma folga acima e abaixo), unida às notas
    // (a nota com linha suplementar sai da pauta e estica o retângulo), e o
    // topo sobe a altura do aviso, que fica dentro da faixa.
    final staffTop = staff.topY - space;
    final staffBottom = staff.topY + (staff.lines - 1) * space + space;
    expect(
      r.rect.top,
      refs.map((b) => b.top).fold(staffTop, (a, b) => a < b ? a : b) -
          scoreBandLabelReserve(2.5 * space),
    );
    expect(
      r.rect.bottom,
      refs.map((b) => b.bottom).fold(staffBottom, (a, b) => a > b ? a : b),
    );
    expect(r.label, _doros);
    expect(r.labelSize, 2.5 * space);
  });

  test(
    'duas pautas do mesmo sistema dão um retângulo só, com o aviso nele',
    () {
      const ids = ['xej0b6o', 'i6oe6f0'];
      final rects = rectsOf(ids, label: _doros);
      expect(rects, hasLength(1));
      expect(rects.single.label, _doros);
      // O retângulo cobre as notas das duas pautas (uma faixa por sistema).
      for (final id in ids) {
        final b = geometry.elementOf(id)!.bbox;
        expect(rects.single.rect.top <= b.top, isTrue, reason: id);
        expect(b.bottom <= rects.single.rect.bottom, isTrue, reason: id);
      }
    },
  );

  /// O nó da cena que é o sistema de [staffId] (a linha que contém a pauta).
  SceneNode systemNodeOf(String staffId) {
    SceneNode? found;
    void walk(SceneNode node) {
      if (found != null) return;
      if (node.className.split(' ').first == 'system' &&
          _subtreeIds(node).contains(staffId)) {
        found = node;
        return;
      }
      for (final child in node.children) {
        if (child is SceneNode) walk(child);
      }
    }

    walk(page.root);
    return found!;
  }

  test('oito compassos num sistema dão uma faixa só, não uma por compasso', () {
    // O sistema da pauta `tdowfwl` tem nove compassos, cada um com a sua
    // pauta de sol e a de fá: agrupar pela pauta daria 18 retângulos.
    final system = systemNodeOf('tdowfwl');
    final measures = _countNodes(system, 'measure');
    expect(measures, greaterThanOrEqualTo(8));

    final sistema = _subtreeIds(system);
    final ids = [
      for (final n in doc.midi!.notes)
        if (geometry.elementOf(n.id) case final ref?
            when ref.page == 0 && sistema.contains(ref.id))
          n.id,
    ];
    expect(ids.length, greaterThan(8));

    final rects = rectsOf(ids, label: _doros);
    expect(rects, hasLength(1));
    expect(rects.single.label, _doros);
  });

  test('o aviso fica dentro do topo da faixa, acima da pauta', () {
    const ids = ['e11eog5', 'xej0b6o'];
    final r = rectsOf(ids, label: _doros).single;
    final staff = page.byId['tdowfwl']!.staffGeometry!;
    final space = 2 * staff.unit;
    final staffTop = staff.topY - space;
    // A letra (1,2 da altura da fonte, com a folga de cima) entra no retângulo
    // e termina acima da pauta.
    expect(r.rect.top + r.labelSize * 1.4 <= staffTop, isTrue);
  });

  test('faixa que atravessa sistemas: um retângulo por sistema', () {
    final rects = rectsOf(['orw55dt', 'xej0b6o'], label: _doros);
    expect(rects, hasLength(2));
    expect(rects.where((r) => r.label != null), hasLength(1));
    final tops = rects.map((r) => r.rect.top).toSet();
    expect(tops, hasLength(2));
  });

  test('id que não existe e id de outra página são ignorados', () {
    final rects = rectsOf([
      'orw55dt',
      'id-que-nao-existe',
      noteOnPageOne(),
    ], label: _doros);
    expect(rects, hasLength(1));
    expect(rects.single.label, _doros);
  });

  test('a primeira nota de outra página não põe o aviso aqui', () {
    final rects = rectsOf([noteOnPageOne(), 'orw55dt'], label: _doros);
    expect(rects, hasLength(1));
    expect(rects.single.label, isNull);
  });

  test('duas faixas vizinhas no mesmo sistema viram uma só, com um aviso', () {
    // Dois trechos do aluno seguidos: a folga de cada lado se cruza, e o
    // resultado tem de ser contínuo, com o aviso só no começo.
    final rects = scoreBandRects(page, 0, geometry, [
      const ScoreBand(['e11eog5'], label: _doros),
      const ScoreBand(['xej0b6o'], label: _doros),
    ]);
    final single = rectsOf(['e11eog5', 'xej0b6o'], label: _doros);
    expect(rects, hasLength(1));
    expect(rects.single.label, _doros);
    expect(rects.single.rect, single.single.rect);
  });

  test('faixas de sistemas diferentes não se juntam', () {
    final rects = scoreBandRects(page, 0, geometry, [
      const ScoreBand(['orw55dt'], label: _doros),
      const ScoreBand(['xej0b6o'], label: _doros),
    ]);
    expect(rects, hasLength(2));
    expect(rects.where((r) => r.label != null), hasLength(2));
  });

  test('faixa vazia dá lista vazia', () {
    expect(rectsOf(const []), isEmpty);
    expect(scoreBandRects(page, 0, geometry, const []), isEmpty);
  });

  test('o controlador avisa quem o escuta quando as faixas mudam', () {
    final controller = ScoreBandController(
      fill: const ui.Color(0x331E6FD9),
      labelColor: const ui.Color(0xFF1E6FD9),
    );
    addTearDown(controller.dispose);
    var calls = 0;
    controller.addListener(() => calls++);
    expect(controller.bands, isEmpty);
    controller.bands = [
      ScoreBand(const ['orw55dt'], label: _doros),
    ];
    expect(controller.bands, hasLength(1));
    controller.clear();
    expect(controller.bands, isEmpty);
    expect(calls, 2);
  });

  testWidgets('a faixa aparece na página e trocar as faixas repinta', (
    tester,
  ) async {
    final controller = ScoreBandController(
      fill: const ui.Color(0x801E6FD9),
      labelColor: const ui.Color(0xFF1E6FD9),
    );
    addTearDown(controller.dispose);
    final p = doc.pages[0];
    final key = await pumpAtSize(
      tester,
      ScorePageView(document: doc, pageIndex: 0, bands: controller),
      p.widthPx,
      p.heightPx,
    );
    final sem = await captureBytes(tester, key, p.widthPx, p.heightPx);

    controller.bands = [
      ScoreBand(const ['e11eog5', 'xej0b6o'], label: _doros),
    ];
    await tester.pump();
    expect(tester.takeException(), isNull);
    final com = await captureBytes(tester, key, p.widthPx, p.heightPx);

    expect(countDifferentPixels(sem, com), greaterThan(0));
  });
}

int _countNodes(SceneNode root, String kind) {
  var n = 0;
  void walk(SceneNode node) {
    if (node.className.split(' ').first == kind) n++;
    for (final child in node.children) {
      if (child is SceneNode) walk(child);
    }
  }

  walk(root);
  return n;
}

/// Os ids de todos os nós de [root] (ele mesmo incluído).
Set<String> _subtreeIds(SceneNode root) {
  final ids = <String>{};
  void walk(SceneNode node) {
    final id = node.id;
    if (id != null) ids.add(id);
    for (final child in node.children) {
      if (child is SceneNode) walk(child);
    }
  }

  walk(root);
  return ids;
}

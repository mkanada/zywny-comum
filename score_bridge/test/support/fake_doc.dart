// Documento sintético para testar a regra da haste (A05b) sem depender do
// corpus: páginas 1000×1400 com compassos e notas de bbox conhecida.
import 'dart:ui';

import 'package:score_bridge/score_bridge.dart';

class FakeNote {
  const FakeNote(this.id, this.left);
  final String id;
  final double left;
}

class FakeMeasure {
  const FakeMeasure(this.id, this.left, this.notes);
  final String id;
  final double left;
  final List<FakeNote> notes;
}

/// `pages[p]` = compassos da página `p`. `timemap` = (tstamp, ids on, ids off).
VsbDocument fakeDocument(
  List<List<FakeMeasure>> pages,
  List<(double, List<String>, List<String>)> timemap,
) {
  ScenePage page(int index, List<FakeMeasure> measures) {
    final elements = <IndexEntry>[];
    final byId = <String, SceneNode>{};
    var path = 0;
    final children = <SceneChild>[];
    for (final m in measures) {
      final noteNodes = <SceneChild>[];
      for (final n in m.notes) {
        final node = SceneNode(
          id: n.id,
          className: 'note',
          hidden: false,
          bbox: Rect.fromLTWH(n.left, 100, 40, 80),
          children: const [],
        );
        noteNodes.add(node);
        byId[n.id] = node;
        elements.add(
          IndexEntry(
            id: n.id,
            className: 'note',
            nodePath: ++path,
            bbox: node.bbox!,
          ),
        );
      }
      final node = SceneNode(
        id: m.id,
        className: 'measure',
        hidden: false,
        bbox: Rect.fromLTWH(m.left, 50, 400, 200),
        children: noteNodes,
      );
      children.add(node);
      byId[m.id] = node;
      elements.add(
        IndexEntry(
          id: m.id,
          className: 'measure',
          nodePath: ++path,
          bbox: node.bbox!,
        ),
      );
    }
    final root = SceneNode(
      className: 'page',
      hidden: false,
      children: children,
    );
    return ScenePage(
      index: index,
      width: 1000,
      height: 1400,
      contentHeight: 1400,
      viewBoxFactor: 1,
      viewBox: const Rect.fromLTWH(0, 0, 1000, 1400),
      baseWidth: 1000,
      baseHeight: 1400,
      userScaleX: 1,
      userScaleY: 1,
      widthPx: 1000,
      heightPx: 1400,
      fit: const PageFit(scale: 1, tx: 0, ty: 0),
      origin: Offset.zero,
      root: root,
      elements: elements,
      byId: byId,
    );
  }

  return VsbDocument(
    manifest: const VsbManifest(
      format: 'vsb',
      version: 1,
      generator: 'test',
      pageCount: 0,
      files: VsbManifestFiles(scene: 'scene.json', glyphs: 'glyphs.json'),
    ),
    glyphs: const {},
    pages: [for (var i = 0; i < pages.length; i++) page(i, pages[i])],
    timemap: [
      for (final (t, on, off) in timemap)
        TimemapEntry(
          tstamp: t,
          on: on,
          off: off,
          restsOn: const [],
          restsOff: const [],
        ),
    ],
  );
}

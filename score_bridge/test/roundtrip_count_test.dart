// Critério de aceite 3: para uma peça do corpus, o nº de nós, formas, usos
// de glifo e runs de texto contados no Dart bate exatamente com o contado
// por um script Python independente sobre o mesmo scene.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

class _Counts {
  int nodes = 0;
  int paths = 0;
  int rects = 0;
  int ellipses = 0;
  int glyphUses = 0;
  int textRuns = 0;

  Map<String, int> toJsonLike() => {
    'nodes': nodes,
    'paths': paths,
    'rects': rects,
    'ellipses': ellipses,
    'glyphUses': glyphUses,
    'textRuns': textRuns,
  };
}

void _walk(SceneNode node, _Counts counts) {
  counts.nodes++;
  for (final child in node.children) {
    switch (child) {
      case SceneNode n:
        _walk(n, counts);
      case ScenePath _:
        counts.paths++;
      case SceneRect _:
        counts.rects++;
      case SceneEllipse _:
        counts.ellipses++;
      case SceneGlyphUse _:
        counts.glyphUses++;
      case SceneText _:
        counts.textRuns++;
    }
  }
}

void main() {
  test('contagem Dart == contagem Python (script independente)', () {
    final fixture = File('test/fixtures/erik-satie.vsb');
    final doc = VsbDocument.fromBytes(fixture.readAsBytesSync());

    final dartCounts = _Counts();
    for (final page in doc.pages) {
      _walk(page.root, dartCounts);
    }

    final python = Process.runSync('python3', [
      'test/scripts/count_elements.py',
      fixture.path,
    ]);
    expect(
      python.exitCode,
      0,
      reason: 'script python falhou: ${python.stderr}',
    );
    final pythonCounts =
        jsonDecode(python.stdout as String) as Map<String, dynamic>;

    expect(dartCounts.toJsonLike(), pythonCounts);
  });
}

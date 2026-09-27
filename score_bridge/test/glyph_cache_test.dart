// Testes de R03a — `GlyphCache`: `glyphId` → `ui.Path` (§4/§4.1).
//
// Cobre os critérios de aceite 2-5 do passo, sobre o fixture real
// `test/fixtures/erik-satie.vsb` (16 glifos no dicionário).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

/// Todos os `glyphId` usados na árvore de [root], em ordem de documento.
List<String> _usedGlyphIds(SceneNode root) {
  final ids = <String>[];
  void walk(SceneNode node) {
    for (final child in node.children) {
      if (child is SceneNode) {
        walk(child);
      } else if (child is SceneGlyphUse) {
        ids.add(child.glyphId);
      }
    }
  }

  walk(root);
  return ids;
}

void main() {
  late VsbDocument doc;

  setUpAll(() {
    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    doc = VsbDocument.fromBytes(bytes);
  });

  test('bbox: contorno bate com GlyphBBox convertida (tol 2.0)', () {
    expect(doc.glyphs.length, greaterThanOrEqualTo(3));
    for (final entry in doc.glyphs.entries) {
      final bounds = doc.glyphCache.pathFor(entry.key).getBounds();
      final expected = entry.value.bbox.toContourRect();
      // A bbox do Verovio inclui os extremos reais das curvas, que podem
      // passar dos vértices — daí a tolerância de 2 unidades de contorno
      // (no corpus isso só acontece em `Leipzig:EAA9`).
      expect(bounds.left, closeTo(expected.left, 2.0), reason: entry.key);
      expect(bounds.top, closeTo(expected.top, 2.0), reason: entry.key);
      expect(bounds.right, closeTo(expected.right, 2.0), reason: entry.key);
      expect(bounds.bottom, closeTo(expected.bottom, 2.0), reason: entry.key);
    }
  });

  test('memoização: 100 chamadas devolvem a mesma instância', () {
    final cache = GlyphCache(doc.glyphs);
    final id = doc.glyphs.keys.first;
    final first = cache.pathFor(id);
    for (var k = 0; k < 100; k++) {
      expect(identical(cache.pathFor(id), first), isTrue);
    }
    expect(cache.builtCount, 1);
  });

  test('fixture real: 16 Paths construídos, nunca 417 usos', () {
    final cache = GlyphCache(doc.glyphs);
    var uses = 0;
    for (final page in doc.pages) {
      for (final id in _usedGlyphIds(page.root)) {
        cache.pathFor(id);
        uses += 1;
      }
    }
    expect(uses, greaterThan(cache.builtCount));
    expect(cache.builtCount, doc.glyphs.length);
    expect(cache.builtCount, 16);
  });

  test('erro: id ausente lança VsbFormatException citando o id', () {
    expect(
      () => GlyphCache(doc.glyphs).pathFor('Leipzig:FFFF'),
      throwsA(
        isA<VsbFormatException>().having(
          (e) => e.toString(),
          'mensagem',
          contains('Leipzig:FFFF'),
        ),
      ),
    );
  });

  test('document.glyphCache é compartilhado por páginas/painters', () {
    expect(identical(doc.glyphCache, doc.glyphCache), isTrue);
    final id = doc.glyphs.keys.first;
    expect(
      identical(doc.glyphCache.pathFor(id), doc.glyphCache.pathFor(id)),
      isTrue,
    );
  });
}

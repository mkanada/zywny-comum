// Faz o parse de um .vsb real do corpus (Erik Satie - Gymnopédie No.1,
// exportado com `-x 42`, copiado para test/fixtures/erik-satie.vsb;
// regenerado em E01b para embutir measureOn no timemap, e de novo em P01c
// para os padrões --header none --footer none --no-instrument-labels) e
// confere contagens/ids conhecidos, além do critério 4 (byId == índice
// exportado em S04).
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  late VsbDocument doc;

  setUpAll(() {
    final bytes = File('test/fixtures/erik-satie.vsb').readAsBytesSync();
    doc = VsbDocument.fromBytes(bytes);
  });

  test('manifest e glifos', () {
    expect(doc.manifest.format, 'vsb');
    expect(doc.manifest.version, 1);
    expect(doc.manifest.pageCount, 2);
    expect(doc.manifest.files.timemap, 'timemap.json');
    expect(doc.glyphs, hasLength(16));
    expect(doc.glyphs.keys, contains('Leipzig:E050'));
    final clef = doc.glyphs['Leipzig:E050']!;
    expect(clef.bbox.x, -10);
    expect(clef.bbox.y, -6550);
    expect(clef.bbox.width, 6470);
    expect(clef.bbox.height, 17380);
    expect(clef.bbox.toContourRect(), const Rect.fromLTRB(-1, -1083, 646, 655));
  });

  test('páginas', () {
    expect(doc.pages, hasLength(2));
    expect(doc.pages[0].index, 0);
    expect(doc.pages[1].index, 1);
    expect(doc.pages[0].widthPx, 2100);
    expect(doc.pages[0].heightPx, 2970);
  });

  test('elements: contagem e ids conhecidos na página 0', () {
    final elements = doc.pages[0].elements;
    // P01c: sem pgHead/pgFoot/label (D-VSB-PADRAO), 1114 (era 1055).
    expect(elements, hasLength(1114));

    final first = elements.first;
    expect(first.id, 'da3kuku');
    expect(first.className, 'mdiv pageMilestone');
    expect(first.nodePath, 1);
    expect(first.bbox, const Rect.fromLTRB(0, 0, 0, 0));

    // O 1º `system` da página, não mais um id fixo: sem cabeçalho gerado, os
    // ids sintéticos de `system`/`score`/`scoreDef` (P01a/P01b não os tocam,
    // mas o layout sem cabeçalho muda quantos nós vêm antes) não são mais
    // 'd1wmfkp6'.
    final system = elements.firstWhere((e) => e.className == 'system');
    expect(system.id, 'xm8ku22');
    expect(system.nodePath, 3);
    expect(system.bbox.left, closeTo(-441, 1e-9));
    expect(system.bbox.top, closeTo(0.16, 1e-9));
    expect(system.bbox.right, closeTo(20010.5, 1e-9));
    expect(system.bbox.bottom, closeTo(4646, 1e-9));

    final last = elements.last;
    expect(last.id, 'v14b0krf');
    expect(last.className, 'text');
    expect(last.nodePath, 1465);
  });

  test('elements: contagem na página 1', () {
    // P01c: sem pgHead/pgFoot/label (D-VSB-PADRAO), 88 (era 170).
    expect(doc.pages[1].elements, hasLength(88));
  });

  test('byId contém exatamente os mesmos ids do índice exportado (S04)', () {
    for (final page in doc.pages) {
      final idsFromIndex = page.elements.map((e) => e.id).toSet();
      expect(page.byId.keys.toSet(), idsFromIndex);
    }
  });

  test('byId aponta para o nó certo (id/class batem)', () {
    final page = doc.pages[0];
    for (final entry in page.elements) {
      final node = page.byId[entry.id];
      expect(node, isNotNull, reason: 'sem nó para id ${entry.id}');
      expect(node!.id, entry.id);
      expect(node.className, entry.className);
    }
  });
}

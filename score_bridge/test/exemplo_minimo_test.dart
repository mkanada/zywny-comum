// Faz o parse de docs/formato/exemplo-minimo.json (o fixture normativo de
// S01) e confere cada campo contra valores escritos à mão — não apenas um
// toString(). Lido diretamente de docs/formato/ (não copiado) para nunca
// divergir do fixture normativo enquanto a especificação evoluir.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  late VsbDocument doc;

  setUpAll(() {
    final file = File('../docs/formato/exemplo-minimo.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    doc = VsbDocument.fromJson(json);
  });

  test('manifest', () {
    expect(doc.manifest.format, 'vsb');
    expect(doc.manifest.version, 1);
    expect(doc.manifest.generator, 'verovio 6.3.0 / bridge 1');
    expect(doc.manifest.pageCount, 1);
    expect(doc.manifest.files.scene, 'scene.json');
    expect(doc.manifest.files.glyphs, 'glyphs.json');
    expect(doc.manifest.files.timemap, 'timemap.json');
  });

  test('glyphs', () {
    expect(doc.glyphs.keys, ['Leipzig:E0A4']);
    final glyph = doc.glyphs['Leipzig:E0A4']!;
    expect(glyph.font, 'Leipzig');
    expect(glyph.codepoint, 'E0A4');
    expect(glyph.unitsPerEm, 2048);
    expect(glyph.horizAdvX, 656);
    expect(glyph.bbox.x, -10);
    expect(glyph.bbox.y, -262);
    expect(glyph.bbox.width, 552);
    expect(glyph.bbox.height, 262);
    expect(glyph.bbox.toContourRect(), const Rect.fromLTRB(-1, 0, 54.2, 26.2));
    expect(glyph.paths, hasLength(1));
    final subpath = glyph.paths.single;
    expect(subpath.closed, isTrue);
    expect(subpath.v, [0, 0, 100, 0, 100, 100, 0, 100]);
    expect(subpath.i, [0, 0, 0, 0, 0, 0, 0, 0]);
    expect(subpath.o, [0, 0, 0, 0, 0, 0, 0, 0]);
  });

  test('pages: um só, com métricas exatas', () {
    expect(doc.pages, hasLength(1));
    final page = doc.pages.single;
    expect(page.index, 0);
    expect(page.width, 2100);
    expect(page.height, 2970);
    expect(page.contentHeight, 2970);
    expect(page.viewBoxFactor, 10.0);
    expect(page.viewBox.left, 0);
    expect(page.viewBox.top, 0);
    expect(page.viewBox.right, 21000);
    expect(page.viewBox.bottom, 29700);
    expect(page.baseWidth, 2100);
    expect(page.baseHeight, 2970);
    expect(page.userScaleX, 1.0);
    expect(page.userScaleY, 1.0);
    expect(page.widthPx, 2100);
    expect(page.heightPx, 2970);
    expect(page.fit.scale, 0.1);
    expect(page.fit.tx, 0.0);
    expect(page.fit.ty, 0.0);
    expect(page.origin.dx, 500);
    expect(page.origin.dy, 500);
  });

  test('root: grupo sem id, 3 filhos (staff, note-1, título)', () {
    final root = doc.pages.single.root;
    expect(root.id, isNull);
    expect(root.className, '');
    expect(root.color, isNull);
    expect(root.hidden, isFalse);
    expect(root.rotate, isNull);
    expect(root.bbox, isNull);
    expect(root.children, hasLength(3));
  });

  test('staff: grupo com pauta (path) e clave (uso de glifo)', () {
    final root = doc.pages.single.root;
    final staff = root.children[0] as SceneNode;
    expect(staff.id, isNull);
    expect(staff.className, 'staff');
    expect(staff.bbox, const Rect.fromLTRB(1000, 1500, 11000, 2100));
    expect(staff.children, hasLength(2));

    final lines = staff.children[0] as ScenePath;
    expect(lines.paths, hasLength(5));
    expect(lines.paths[0].closed, isFalse);
    expect(lines.paths[0].v, [1000, 1500, 11000, 1500]);
    expect(lines.paths[4].v, [1000, 2100, 11000, 2100]);
    expect(lines.fill, ScenePaint.none);
    expect((lines.stroke as ColorPaint).hex, '#000000');
    expect(lines.strokeWidth, 10);
    expect(lines.fillOpacity, 1.0);
    expect(lines.strokeOpacity, 1.0);
    expect(lines.lineCap, SceneLineCap.defaultCap);
    expect(lines.lineJoin, SceneLineJoin.defaultJoin);
    expect(lines.dash, isNull);

    final clef = staff.children[1] as SceneGlyphUse;
    expect(clef.glyphId, 'Leipzig:E0A4');
    expect(clef.x, 1000);
    expect(clef.y, 1500);
    expect(clef.sx, 3.2);
    expect(clef.sy, 3.2);
    expect(clef.fill, ScenePaint.inherit);
    expect(clef.stroke, ScenePaint.inherit);
    expect(clef.strokeWidth, isNull);
  });

  test('note-1: grupo endereçável, cor própria, path sem estilo (herda)', () {
    final root = doc.pages.single.root;
    final note = root.children[1] as SceneNode;
    expect(note.id, 'note-1');
    expect(note.className, 'note');
    expect(note.color, '#ff0000');
    expect(note.hidden, isFalse);
    expect(note.bbox, const Rect.fromLTRB(3000, 1550, 3700, 2200));
    expect(note.children, hasLength(1));

    final notehead = note.children.single as ScenePath;
    expect(notehead.paths, hasLength(2));
    expect(notehead.paths[0].closed, isTrue);
    expect(notehead.paths[0].v, [
      3000,
      1900,
      3300,
      1750,
      3600,
      1900,
      3300,
      2050,
    ]);
    expect(notehead.paths[1].closed, isFalse);
    expect(notehead.paths[1].v, [3600, 1900, 3600, 1550]);
    expect(notehead.fill, ScenePaint.inherit);
    expect(notehead.stroke, ScenePaint.inherit);
  });

  test('título: run de texto comum', () {
    final root = doc.pages.single.root;
    final title = root.children[2] as SceneText;
    expect(title.text, 'Título');
    expect(title.x, 1000);
    expect(title.y, 800);
    expect(title.size, 360.0);
    expect(title.align, SceneTextAlign.left);
    expect(title.letterSpacing, 0.0);
    expect(title.bold, isTrue);
    expect(title.italic, isFalse);
    expect(title.family, 'Liberation Serif');
    expect(title.color, '#000000');
  });

  test('elements: índice plano com a nota', () {
    final elements = doc.pages.single.elements;
    expect(elements, hasLength(1));
    final entry = elements.single;
    expect(entry.id, 'note-1');
    expect(entry.className, 'note');
    expect(entry.nodePath, 2);
    expect(entry.bbox, const Rect.fromLTRB(3000, 1550, 3700, 2200));
  });

  test('byId: contém a nota indexada, apontando para o mesmo nó', () {
    final page = doc.pages.single;
    expect(page.byId.keys, ['note-1']);
    expect(page.byId['note-1'], same(page.root.children[1]));
  });

  test('timemap: um instante com a nota', () {
    expect(doc.timemap, hasLength(1));
    final entry = doc.timemap!.single;
    expect(entry.qstamp, 0.0);
    expect(entry.tstamp, 1.0);
    expect(entry.on, ['note-1']);
    expect(entry.off, isEmpty);
    expect(entry.restsOn, isEmpty);
    expect(entry.restsOff, isEmpty);
    expect(entry.tempo, isNull);
    expect(entry.measureOn, isNull);
    expect(entry.qfrac, isNull);
  });
}

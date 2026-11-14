// Retângulo da cabeça da nota (ND05): a caixa do glifo que a cena desenha no
// nó `notehead`, sem a haste, no sistema de pixels do `overlayBuilder`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

/// `glyphId` do primeiro glifo dentro de um nó `notehead` (o da cabeça).
String? _headGlyphOf(SceneNode node, {bool inHead = false}) {
  final head = inHead || node.className.split(' ').contains('notehead');
  for (final child in node.children) {
    if (child is SceneGlyphUse && head) return child.glyphId;
    if (child is SceneNode) {
      final found = _headGlyphOf(child, inHead: head);
      if (found != null) return found;
    }
  }
  return null;
}

/// A nota tem haste (um nó `stem` na árvore dela).
bool _hasStem(SceneNode node) => node.children.any(
  (c) =>
      c is SceneNode &&
      (c.className.split(' ').contains('stem') || _hasStem(c)),
);

void _checkNoteheads(VsbDocument doc) {
  final pitch = doc.pitchPos;
  expect(pitch, isNotNull, reason: 'o corpus tem pitchpos.json');
  final geometry = doc.geometry;
  var notes = 0;
  var stems = 0;
  var rests = 0;
  var widthsChecked = 0;

  for (final entry in pitch!.events.entries) {
    final id = entry.key;
    final ref = geometry.elementOf(id);
    if (ref == null) continue;
    final page = doc.pages[ref.page];
    final node = page.byId[ref.id]!;

    if (!entry.value.isNote) {
      rests++;
      expect(geometry.noteheadRectOf(id), isNull, reason: 'pausa $id');
      continue;
    }
    notes++;
    final head = geometry.noteheadRectOf(id);
    final note = geometry.rectForId(id)!;
    expect(head, isNotNull, reason: 'nota $id sem cabeça');
    if (head == null) continue;

    // 1. A cabeça cabe dentro da nota (com 1 px de folga).
    expect(
      head.left >= note.left - 1 &&
          head.right <= note.right + 1 &&
          head.top >= note.top - 1 &&
          head.bottom <= note.bottom + 1,
      isTrue,
      reason: 'cabeça $head fora da nota $note ($id)',
    );

    // 2. Com haste, a cabeça é bem menor que a nota inteira.
    if (_hasStem(node)) {
      stems++;
      expect(
        head.height,
        lessThan(note.height / 2),
        reason: 'nota com haste $id',
      );
    }

    // 3. A largura é a do glifo que o fantasma usa. O fantasma sempre mede a
    //    cabeça preta (E0A4), então a comparação vale para as notas pretas.
    final glyphId = _headGlyphOf(node);
    if (glyphId != null && glyphId.endsWith(':E0A4')) {
      final ghosts = doc.ghostsFor(expectedIds: [id], wrongKeys: [60]);
      if (ghosts.isNotEmpty) {
        widthsChecked++;
        expect(
          head.width,
          closeTo(ghosts.first.headWidth * page.fit.scale, 1.0),
          reason: 'largura da cabeça de $id',
        );
      }
    }

    // 4. Com a página desenhada na metade da largura, tudo cai pela metade.
    final half = geometry.noteheadRectOf(id, pageWidth: page.widthPx / 2);
    expect(half, isNotNull);
    expect(half!.left, closeTo(head.left / 2, 0.01));
    expect(half.top, closeTo(head.top / 2, 0.01));
    expect(half.width, closeTo(head.width / 2, 0.01));
    expect(half.height, closeTo(head.height / 2, 0.01));
  }

  // Os contadores garantem que o teste cobriu notas, hastes, pausas e larguras.
  expect(notes, greaterThan(0), reason: 'a partitura tem notas');
  expect(stems, greaterThan(0), reason: 'a partitura tem nota com haste');
  expect(rests, greaterThan(0), reason: 'a partitura tem pausa');
  expect(widthsChecked, greaterThan(0), reason: 'nenhuma largura comparada');
  // 5. Id sem nó não tem cabeça.
  expect(geometry.noteheadRectOf('nao-existe-no-documento'), isNull);
}

void main() {
  final corpus = corpusDoc('Nocturne');
  if (corpus == null) {
    test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
  } else {
    test('cabeça da nota no corpus', () => _checkNoteheads(corpus));
  }

  // A mesma checagem no fixture do fantasma, que vem no repositório: roda
  // mesmo sem o corpus de partituras.
  final satie = VsbDocument.fromBytes(
    File('test/fixtures/fantasma/satie.vsb').readAsBytesSync(),
  );
  test('cabeça da nota no satie.vsb', () => _checkNoteheads(satie));
}

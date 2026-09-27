// Cache de contornos de glifo (R03a).
//
// Cada `glyphId` do dicionário é convertido uma única vez por documento (em
// unidades de fonte, via `pathFromBeziers` de R02a) e compartilhado por todas
// as páginas e todas as ocorrências. O cache vive no `VsbDocument`
// (`document.glyphCache`), não no painter.
//
// Os contornos já vêm no sistema de coordenadas de tela (o
// `transform="scale(1,-1)"` do XML foi aplicado na exportação, S03): nada é
// invertido aqui. A bbox de metadados (`GlyphBBox`, escala ×10 com Y para
// cima) só serve para comparação via `toContourRect()` (S08).
library;

import 'dart:ui' as ui;

import 'geometry.dart';
import 'model.dart';

/// Contornos de glifo memoizados por `glyphId` (`"<fonte>:<codepoint>"`).
class GlyphCache {
  GlyphCache(this.glyphs);

  final Map<String, GlyphDef> glyphs;

  final Map<String, ui.Path> _built = {};

  /// Quantos `Path` já foram construídos (instrumentação para teste).
  int get builtCount => _built.length;

  /// Devolve o contorno do glifo em unidades de fonte, construindo e
  /// memoizando na primeira chamada.
  ///
  /// Lança [VsbFormatException] se o id não está no dicionário: desenhar
  /// nada silenciosamente esconderia um bug de exportação.
  ui.Path pathFor(String glyphId) {
    final cached = _built[glyphId];
    if (cached != null) {
      return cached;
    }
    final def = glyphs[glyphId];
    if (def == null) {
      throw VsbFormatException('u.g', 'glifo "$glyphId" ausente do dicionário');
    }
    final path = pathFromBeziers(def.paths);
    _built[glyphId] = path;
    return path;
  }
}

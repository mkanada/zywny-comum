// Pausa substituta (L03): a pausa que ocupa o lugar de uma coluna escondida.
// Porta das regras 4-7 da §11 de docs/formato/especificacao-v1.md; a referência
// executável é compare/scripts/hide_ref.py (`stand_in`) do bridge, e os vetores
// de teste estão em test/fixtures/sumico/vetores.json (`esperado.standIn`).
library;

import 'hide.dart';
import 'model.dart';

/// `dur` → ponto de código do glifo da pausa (regra 5): semibreve (`E4E3`) a
/// semifusa (`E4E9`). Fora dessa faixa não há pausa substituta.
const Map<int, String> kRestCodepoint = {
  1: 'E4E3',
  2: 'E4E4',
  4: 'E4E5',
  8: 'E4E6',
  16: 'E4E7',
  32: 'E4E8',
  64: 'E4E9',
};

/// Um ponto de aumento da pausa: um círculo `fill` na cor dela, sem contorno
/// (o Verovio os desenha assim, não com o glifo `E1E7`).
class StandInDot {
  const StandInDot({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
  });

  final double cx;
  final double cy;
  final double rx;
  final double ry;
}

/// A pausa de uma coluna escondida, no referencial de conteúdo da página
/// (§5.1): onde, com que glifo e que escala.
class StandInRest {
  const StandInRest({
    required this.page,
    required this.staffId,
    required this.glyphId,
    required this.dur,
    required this.x,
    required this.y,
    required this.sx,
    required this.sy,
    required this.loc,
    required this.dots,
  });

  /// Página em que a coluna está (onde a pausa é desenhada).
  final PageRef page;

  /// `id` do nó `staff` de desenho da coluna (a pauta onde a pausa fica).
  final String? staffId;

  /// Chave em [VsbDocument.glyphs] (`"<fonte>:E4E5"`).
  final String glyphId;

  /// A figura escrita da nota mais curta da coluna (regra 4).
  final int dur;
  final double x;
  final double y;
  final double sx;
  final double sy;

  /// Posição vertical da pausa na pauta (regra 6): `0` é a linha de baixo.
  final int loc;

  /// Os pontos de aumento, vazio sem ponto.
  final List<StandInDot> dots;
}

/// A `loc` da pausa padrão de uma pauta de [lines] linhas (regra 6).
int _restLoc(int dur, int lines) {
  var loc = lines - 1;
  if (dur <= 2 && loc.isOdd) loc -= 1;
  if (dur == 1 && lines > 1) loc += 2;
  return loc;
}

extension VsbStandInRest on VsbDocument {
  /// A pausa que substitui a coluna [noteIds] (os ids **notados** das notas de
  /// uma pauta de desenho; ids expandidos `-rend<N>` valem), ou `null` quando
  /// não dá para calcular: alguma nota sem `dur` (`.vsb` anterior a G08b ou
  /// figura desconhecida), `dur` ≥ 128, glifo ausente do dicionário, pauta que
  /// não tem 5 linhas, ids que não estão na página, ou notas de pautas de
  /// desenho diferentes. A coluna é escondida do mesmo jeito; só não se desenha
  /// nada (§11, regras 4-5).
  ///
  /// [page] é onde procurar as notas (padrão: a página normal que contém a
  /// primeira). Especificação: §11, regras 4-7.
  StandInRest? standInFor(List<String> noteIds, {PageRef? page}) {
    final pitchPos = this.pitchPos;
    if (pitchPos == null || noteIds.isEmpty) return null;
    final notated = <String>[for (final id in noteIds) ?sceneIdOf(id)];
    if (notated.length != noteIds.length) return null;

    final PageRef ref;
    final HidePageIndex index;
    if (page != null) {
      ref = page;
      index = HidePageIndex.of(this, pageAt(page));
    } else {
      PageRef? found;
      for (var i = 0; i < pages.length; i++) {
        if (HidePageIndex.of(this, pages[i]).staffOfNote(notated.first) !=
            null) {
          found = PageRef(i);
          break;
        }
      }
      if (found == null) return null;
      ref = found;
      index = HidePageIndex.of(this, pageAt(found));
    }

    // Uma pauta de desenho só.
    final staff = index.staffOfNote(notated.first);
    if (staff == null) return null;
    for (final id in notated) {
      if (!identical(index.staffOfNote(id), staff)) return null;
    }
    final geometry = staff.staffGeometry;
    if (geometry == null || geometry.lines != 5) return null;

    // Regra 4: a figura da nota mais curta (maior `dur`; no empate, menos
    // pontos).
    var dur = 0;
    var dots = 0;
    for (final id in notated) {
      final event = pitchPos.events[id];
      final d = event?.dur;
      if (event == null || d == null) return null;
      if (d > dur) {
        dur = d;
        dots = event.dots;
      } else if (d == dur && event.dots < dots) {
        dots = event.dots;
      }
    }

    // Regra 5: o glifo.
    final codepoint = kRestCodepoint[dur];
    if (codepoint == null) return null;
    final font = glyphs.keys.first.split(':').first;
    final glyphId = '$font:$codepoint';
    final glyph = glyphs[glyphId];
    if (glyph == null) return null;

    // Regra 6: x da cabeça mais à esquerda; y pela linha do meio.
    double? x;
    for (final id in notated) {
      for (final head in index.headsOfNote(id)) {
        if (x == null || head.x < x) x = head.x;
      }
    }
    if (x == null) return null;
    final top = geometry.topY;
    final unit = geometry.unit;
    final lines = geometry.lines;
    final loc = _restLoc(dur, lines);
    final y = top + (2 * (lines - 1) - loc) * unit;
    final sx = geometry.glyphScaleX;
    final sy = geometry.glyphScaleY;

    // Pontos de aumento (View::DrawDots): círculos de raio `max(2·unit/5, 2)`.
    final dotList = <StandInDot>[];
    if (dots > 0) {
      var locDot = loc;
      if (locDot.isEven) locDot += 1;
      if (dur == 32 || dur == 64) locDot += 2;
      // O Verovio calcula em inteiros: a largura do glifo é truncada.
      final xRel = dur > 2
          ? (glyph.bbox.width / 10.0 * sx).floor()
          : (2.5 * unit).floor();
      final x0 = x + xRel + unit;
      final yDot = top + (2 * (lines - 1) - locDot) * unit;
      final r = (2 * unit / 5) > 2 ? 2 * unit / 5 : 2.0;
      for (var j = 0; j < dots; j++) {
        dotList.add(
          StandInDot(cx: x0 + j * 1.5 * unit, cy: yDot, rx: r, ry: r),
        );
      }
    }

    return StandInRest(
      page: ref,
      staffId: staff.id,
      glyphId: glyphId,
      dur: dur,
      x: x,
      y: y,
      sx: sx,
      sy: sy,
      loc: loc,
      dots: dotList,
    );
  }
}

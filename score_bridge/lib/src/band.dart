// Faixa atrás das notas (T18 LP03): um fundo colorido por trás de um grupo de
// notas (a parte do aluno), da primeira à última, cortado na quebra de linha,
// com um aviso ("você") acima da primeira nota.
//
// A faixa é pintada no `_PagePainter`, depois do fundo e antes das notas: é
// por baixo do halo e das notas escondidas, por isso não é uma camada por
// cima (como as pausas substitutas). O pacote não sabe o que é aluno: recebe
// ids e desenha. Quem escolhe os ids é o app.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'hit_test.dart';
import 'model.dart';

/// Uma faixa: o fundo atrás das notas [noteIds] (ids da cena ou expandidos),
/// do primeiro ao último, um retângulo por pauta de sistema; [label] (ex.:
/// "você") acima da primeira nota.
@immutable
class ScoreBand {
  const ScoreBand(this.noteIds, {this.label});

  final List<String> noteIds;
  final String? label;
}

/// Um retângulo de faixa numa página, no espaço de conteúdo (o das bbox do
/// [ScoreGeometry]). [label] só no retângulo que tem a primeira nota da faixa;
/// [labelSize] é a altura da letra, no mesmo espaço.
@immutable
class ScoreBandRect {
  const ScoreBandRect(this.rect, {this.label, this.labelSize = 0});

  final ui.Rect rect;
  final String? label;
  final double labelSize;
}

/// Índice de uma página: a pauta ancestral de cada id e os nós de pauta.
/// Montado uma vez por página (o `Expando` abaixo), como o da nota fantasma.
class _BandPageIndex {
  _BandPageIndex(ScenePage page) {
    _walk(page.root, null);
  }

  /// id do nó → id da pauta que o contém (`null` se nenhuma).
  final Map<String, String?> staffIdOf = {};

  /// id da pauta → nó da pauta (com a geometria dela).
  final Map<String, SceneNode> staves = {};

  void _walk(SceneNode node, String? staffId) {
    if (node.className.split(' ').first == 'staff') {
      staffId = node.id;
      final id = node.id;
      if (id != null) staves[id] = node;
    }
    final id = node.id;
    if (id != null) staffIdOf[id] = staffId;
    for (final child in node.children) {
      if (child is SceneNode) _walk(child, staffId);
    }
  }
}

final Expando<_BandPageIndex> _bandIndexes = Expando();

/// Os retângulos das [bands] na página [pageIndex] de [page], com a geometria
/// [geometry] (a do escopo da página). Função pura: os testes a chamam direto.
///
/// Por faixa: as notas que estão nesta página e numa pauta são agrupadas pela
/// pauta (uma faixa que atravessa a quebra de linha vira um retângulo por
/// sistema). Nota sem pauta é ignorada.
List<ScoreBandRect> scoreBandRects(
  ScenePage page,
  int pageIndex,
  ScoreGeometry geometry,
  List<ScoreBand> bands,
) {
  final index = _bandIndexes[page] ??= _BandPageIndex(page);
  final out = <ScoreBandRect>[];
  for (final band in bands) {
    if (band.noteIds.isEmpty) continue;
    final firstId = band.noteIds.first;

    // Notas desta página agrupadas pela pauta, na ordem dos ids da faixa.
    final groups = <String, List<ElementRef>>{};
    for (final id in band.noteIds) {
      final ref = geometry.elementOf(id);
      if (ref == null || ref.page != pageIndex) continue;
      final staffId = _staffIdOf(page, index, ref);
      if (staffId == null) continue;
      groups.putIfAbsent(staffId, () => []).add(ref);
    }

    // A primeira nota da faixa define em qual retângulo cai o aviso.
    final firstRef = geometry.elementOf(firstId);
    final firstStaff = firstRef == null || firstRef.page != pageIndex
        ? null
        : _staffIdOf(page, index, firstRef);
    for (final entry in groups.entries) {
      final staff = index.staves[entry.key]!;
      final rect = _groupRect(entry.value, staff.staffGeometry);
      final space = _spaceOf(entry.value, staff.staffGeometry);
      final hasLabel = band.label != null && entry.key == firstStaff;
      out.add(
        ScoreBandRect(
          rect,
          label: hasLabel ? band.label : null,
          labelSize: 2.5 * space,
        ),
      );
    }
  }
  return out;
}

/// A pauta que desenha a nota [ref] (id da cena), ou `null` se ela não tem
/// pauta. Nota desenhada noutra pauta (cruzamento de mão) segue a de `staffRef`.
String? _staffIdOf(ScenePage page, _BandPageIndex index, ElementRef ref) {
  final node = page.byId[ref.id];
  if (node == null) return null;
  final staffId = node.staffRef ?? index.staffIdOf[ref.id];
  if (staffId == null || !index.staves.containsKey(staffId)) return null;
  return staffId;
}

/// A distância entre duas linhas da pauta (ou, sem pauta, a metade da altura
/// das notas, a folga que o retângulo também usa).
double _spaceOf(List<ElementRef> refs, StaffGeometry? staff) {
  if (staff != null) return 2 * staff.unit;
  return refs.map((r) => r.bbox.height).reduce(math.max) / 2;
}

/// O retângulo de um grupo de notas da mesma pauta. Com a pauta: a largura das
/// notas com uma distância de folga de cada lado, e a altura da pauta (com uma
/// folga acima e abaixo), unida às notas (a linha suplementar sai da pauta).
/// Sem a pauta: só as bbox das notas, com folga de metade da altura delas.
ui.Rect _groupRect(List<ElementRef> refs, StaffGeometry? staff) {
  var left = double.infinity;
  var right = double.negativeInfinity;
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  for (final r in refs) {
    left = math.min(left, r.bbox.left);
    right = math.max(right, r.bbox.right);
    top = math.min(top, r.bbox.top);
    bottom = math.max(bottom, r.bbox.bottom);
  }
  if (staff == null) {
    final pad = _spaceOf(refs, null);
    return ui.Rect.fromLTRB(left - pad, top - pad, right + pad, bottom + pad);
  }
  final space = 2 * staff.unit;
  final staffTop = staff.topY - space;
  final staffBottom = staff.topY + (staff.lines - 1) * space + space;
  return ui.Rect.fromLTRB(
    left - space,
    math.min(top, staffTop),
    right + space,
    math.max(bottom, staffBottom),
  );
}

/// Controlador das faixas da partitura e suas cores; o `ScorePageView`
/// repinta quando [bands] muda.
class ScoreBandController extends ChangeNotifier {
  ScoreBandController({required this.fill, required this.labelColor});

  /// O fundo da faixa (com a opacidade que o app escolher).
  final ui.Color fill;

  /// A cor do aviso.
  final ui.Color labelColor;

  List<ScoreBand> _bands = const [];

  List<ScoreBand> get bands => _bands;

  set bands(List<ScoreBand> value) {
    _bands = value;
    notifyListeners();
  }

  void clear() => bands = const [];
}

/// Pinta as faixas [rects]: o fundo com cantos arredondados (raio
/// `rect.height / 12`) e o aviso, em negrito, com a base a `labelSize / 3`
/// acima do topo do retângulo, alinhado à esquerda dele.
void paintScoreBands(
  ui.Canvas canvas,
  List<ScoreBandRect> rects, {
  required ui.Color fill,
  required ui.Color labelColor,
}) {
  final paint = ui.Paint()..color = fill;
  for (final r in rects) {
    final radius = r.rect.height / 12;
    canvas.drawRRect(ui.RRect.fromRectXY(r.rect, radius, radius), paint);
    final label = r.label;
    if (label == null) continue;
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: r.labelSize,
          color: labelColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      ui.Offset(r.rect.left, r.rect.top - r.labelSize / 3 - text.height),
    );
    text.dispose();
  }
}

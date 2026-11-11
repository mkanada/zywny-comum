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
/// do primeiro ao último, um retângulo por sistema (a linha da partitura, com
/// os compassos dela); [label] (ex.: "você") dentro do topo, sobre a primeira
/// nota.
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

/// Índice de uma página: a pauta ancestral de cada id, o sistema de cada pauta e
/// os nós de pauta. Montado uma vez por página (o `Expando` abaixo), como o da
/// nota fantasma.
class _BandPageIndex {
  _BandPageIndex(ScenePage page) {
    _walk(page.root, null, null);
  }

  /// id do nó → id da pauta que o contém (`null` se nenhuma).
  final Map<String, String?> staffIdOf = {};

  /// id da pauta → nó da pauta (com a geometria dela).
  final Map<String, SceneNode> staves = {};

  /// id da pauta → nó do sistema que a contém (`null` se nenhum).
  final Map<String, SceneNode?> systemOfStaff = {};

  void _walk(SceneNode node, String? staffId, SceneNode? system) {
    final kind = node.className.split(' ').first;
    // O sistema é a linha da partitura. Cada compasso tem as suas pautas (uma
    // por nó), então a faixa agrupa pelo sistema, não pela pauta.
    if (kind == 'system') system = node;
    if (kind == 'staff') {
      staffId = node.id;
      final id = node.id;
      if (id != null) {
        staves[id] = node;
        systemOfStaff[id] = system;
      }
    }
    final id = node.id;
    if (id != null) staffIdOf[id] = staffId;
    for (final child in node.children) {
      if (child is SceneNode) _walk(child, staffId, system);
    }
  }
}

final Expando<_BandPageIndex> _bandIndexes = Expando();

/// As notas de uma faixa que estão num mesmo sistema, e as pautas em que elas
/// são desenhadas.
class _BandGroup {
  final List<ElementRef> refs = [];
  final Map<String, SceneNode> staves = {};

  void add(ElementRef ref, String staffId, SceneNode staff) {
    refs.add(ref);
    staves[staffId] = staff;
  }
}

/// Os retângulos das [bands] na página [pageIndex] de [page], com a geometria
/// [geometry] (a do escopo da página). Função pura: os testes a chamam direto.
///
/// Por faixa: as notas que estão nesta página e numa pauta são agrupadas pelo
/// sistema, um retângulo por sistema (uma faixa que atravessa a quebra de linha
/// vira um retângulo por linha, e um sistema de oito compassos vira um só).
/// Nota sem pauta é ignorada.
List<ScoreBandRect> scoreBandRects(
  ScenePage page,
  int pageIndex,
  ScoreGeometry geometry,
  List<ScoreBand> bands,
) {
  final index = _bandIndexes[page] ??= _BandPageIndex(page);
  final out = <(Object, ScoreBandRect)>[];
  for (final band in bands) {
    if (band.noteIds.isEmpty) continue;
    final firstId = band.noteIds.first;
    // Notas desta página agrupadas pelo sistema, na ordem dos ids da faixa.
    final groups = <Object, _BandGroup>{};
    for (final id in band.noteIds) {
      final ref = geometry.elementOf(id);
      if (ref == null || ref.page != pageIndex) continue;
      final staffId = _staffIdOf(page, index, ref);
      if (staffId == null) continue;
      groups
          .putIfAbsent(_groupOf(index, staffId), () => _BandGroup())
          .add(ref, staffId, index.staves[staffId]!);
    }
    // A primeira nota da faixa define em qual retângulo cai o aviso.
    final firstRef = geometry.elementOf(firstId);
    final firstStaff = firstRef == null || firstRef.page != pageIndex
        ? null
        : _staffIdOf(page, index, firstRef);
    final firstGroup = firstStaff == null ? null : _groupOf(index, firstStaff);
    for (final entry in groups.entries) {
      final hasLabel = band.label != null && entry.key == firstGroup;
      final space = _spaceOf(
        entry.value.refs,
        _firstGeometry(entry.value.staves.values),
      );
      out.add((
        entry.key,
        ScoreBandRect(
          _groupRect(entry.value, label: hasLabel),
          label: hasLabel ? band.label : null,
          labelSize: 2.5 * space,
        ),
      ));
    }
  }
  return _mergeOverlapping(out);
}

/// Junta as faixas que se tocam ou se sobrepõem no mesmo sistema (dois trechos
/// vizinhos do aluno, cuja folga de cada lado se cruza): uma faixa contínua, com
/// um aviso só (o do retângulo mais à esquerda que tem um). Faixas de sistemas
/// diferentes, ou separadas por um vão, ficam como estão.
List<ScoreBandRect> _mergeOverlapping(List<(Object, ScoreBandRect)> entries) {
  final byGroup = <Object, List<ScoreBandRect>>{};
  for (final (group, rect) in entries) {
    byGroup.putIfAbsent(group, () => []).add(rect);
  }
  final out = <ScoreBandRect>[];
  for (final rects in byGroup.values) {
    rects.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    var current = rects.first;
    for (final next in rects.skip(1)) {
      if (next.rect.left > current.rect.right) {
        out.add(current);
        current = next;
        continue;
      }
      final withLabel = current.label != null ? current : next;
      current = ScoreBandRect(
        current.rect.expandToInclude(next.rect),
        label: withLabel.label,
        labelSize: withLabel.labelSize,
      );
    }
    out.add(current);
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

/// A chave do sistema de uma pauta: o nó do sistema que a contém, ou a própria
/// pauta se ele não existe (a cena sempre tem o sistema).
Object _groupOf(_BandPageIndex index, String staffId) =>
    index.systemOfStaff[staffId] ?? index.staves[staffId]!;

/// A geometria da primeira pauta que a tem, ou `null`.
StaffGeometry? _firstGeometry(Iterable<SceneNode> staves) {
  for (final staff in staves) {
    if (staff.staffGeometry != null) return staff.staffGeometry;
  }
  return null;
}

/// A distância entre duas linhas da pauta (ou, sem pauta, a metade da altura
/// das notas, a folga que o retângulo também usa).
double _spaceOf(List<ElementRef> refs, StaffGeometry? staff) {
  if (staff != null) return 2 * staff.unit;
  return refs.map((r) => r.bbox.height).reduce(math.max) / 2;
}

/// A altura que o aviso pede no topo da faixa: a letra ([labelSize]) mais a
/// folga de cada lado (uns 0,2 da letra), para o texto caber dentro do
/// retângulo, acima das pautas.
double scoreBandLabelReserve(double labelSize) => labelSize * 1.6;

/// O retângulo de um sistema: da nota mais à esquerda à mais à direita, com uma
/// distância de folga de cada lado. Em cima e embaixo, as pautas que as notas
/// usam (com uma folga), unidas às notas (a linha suplementar sai da pauta).
/// Sem pauta: só as bbox das notas, com folga de metade da altura delas. Com
/// [label], o topo sobe a altura do aviso, que fica dentro da faixa.
ui.Rect _groupRect(_BandGroup group, {required bool label}) {
  final refs = group.refs;
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
  final staves = [
    for (final s in group.staves.values)
      if (s.staffGeometry != null) s.staffGeometry!,
  ];
  final space = _spaceOf(refs, staves.isEmpty ? null : staves.first);
  if (staves.isEmpty) {
    top -= space;
    bottom += space;
  } else {
    var staffTop = double.infinity;
    var staffBottom = double.negativeInfinity;
    for (final g in staves) {
      final s = 2 * g.unit;
      staffTop = math.min(staffTop, g.topY - s);
      staffBottom = math.max(staffBottom, g.topY + (g.lines - 1) * s + s);
    }
    top = math.min(top, staffTop);
    bottom = math.max(bottom, staffBottom);
  }
  if (label) top -= scoreBandLabelReserve(2.5 * space);
  return ui.Rect.fromLTRB(left - space, top, right + space, bottom);
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
/// `rect.height / 12`) e o aviso, em negrito, dentro do topo do retângulo, à
/// esquerda dele, com uma folga de um quinto da letra.
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
      ui.Offset(
        r.rect.left + r.labelSize * 0.2,
        r.rect.top + r.labelSize * 0.2,
      ),
    );
    text.dispose();
  }
}

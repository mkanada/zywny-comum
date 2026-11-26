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
import 'package:zywny_bloc/zywny_bloc.dart';

import 'hit_test.dart';
import 'model.dart';

/// Uma faixa: o fundo atrás das notas [noteIds] (ids da cena ou expandidos),
/// do primeiro ao último, um retângulo por sistema (a linha da partitura, com
/// os compassos dela); [label] (ex.: "você") dentro do topo, sobre a primeira
/// nota.
@immutable
class ScoreBand {
  const ScoreBand(this.noteIds, {this.label, this.fill});

  final List<String> noteIds;
  final String? label;

  /// A cor desta faixa; `null` usa a do cubit ([ScoreBandCubit.fill]).
  final ui.Color? fill;
}

/// Um retângulo de faixa numa página, no espaço de conteúdo (o das bbox do
/// [ScoreGeometry]). [label] só no retângulo que leva o aviso (um por sistema e
/// cor); [labelSize] é a altura da letra, no mesmo espaço, e [labelLeft] a
/// posição em x do texto (`null` sem aviso: o padrão é um pouco depois da borda
/// esquerda, mas o aviso desvia do andamento, que fica no mesmo topo).
@immutable
class ScoreBandRect {
  const ScoreBandRect(
    this.rect, {
    this.label,
    this.labelSize = 0,
    this.fill,
    this.labelLeft,
  });

  final ui.Rect rect;
  final String? label;
  final double labelSize;

  /// A cor do retângulo (a da [ScoreBand] que o gerou); `null` é a do controlador.
  final ui.Color? fill;

  /// A borda esquerda do texto do aviso, no espaço de conteúdo.
  final double? labelLeft;
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

  /// As caixas do andamento (`tempo`, ♩ = 100) da página: o aviso da faixa não
  /// pode cobri-las. Só as que têm bbox e estão visíveis.
  final List<ui.Rect> marks = [];

  void _walk(SceneNode node, String? staffId, SceneNode? system) {
    final kind = node.className.split(' ').first;
    if (kind == 'tempo' && !node.hidden && node.bbox != null) {
      marks.add(node.bbox!);
    }
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
  final pieces = <_BandPiece>[];
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
    // A primeira nota da faixa define em qual sistema o aviso é candidato.
    final firstRef = geometry.elementOf(firstId);
    final firstStaff = firstRef == null || firstRef.page != pageIndex
        ? null
        : _staffIdOf(page, index, firstRef);
    final firstGroup = firstStaff == null ? null : _groupOf(index, firstStaff);
    for (final entry in groups.entries) {
      pieces.add(
        _BandPiece(
          group: entry.key,
          rect: _groupRect(entry.value, labelSize: null),
          space: _spaceOf(
            entry.value.refs,
            _firstGeometry(entry.value.staves.values),
          ),
          fill: band.fill,
          label: band.label != null && entry.key == firstGroup
              ? band.label
              : null,
        ),
      );
    }
  }
  return _placeLabels(pieces, index.marks);
}

/// Um pedaço de faixa (um sistema de uma faixa) antes de juntar: o retângulo sem
/// o aviso, a distância entre linhas que dá a letra e, se a faixa tem aviso e a
/// primeira nota cai aqui, o texto dele ([label]).
class _BandPiece {
  const _BandPiece({
    required this.group,
    required this.rect,
    required this.space,
    required this.fill,
    required this.label,
  });

  /// O sistema (ou a pauta, sem sistema) do pedaço.
  final Object group;
  final ui.Rect rect;
  final double space;
  final ui.Color? fill;
  final String? label;
}

/// Os pedaços de um mesmo sistema e cor que se tocam ou se sobrepõem: uma faixa
/// contínua, com a união dos retângulos e o aviso do que tem um (o mais à
/// esquerda).
class _BandRun {
  _BandRun(_BandPiece first)
    : rect = first.rect,
      fill = first.fill,
      label = first.label,
      labelSpace = first.space;

  ui.Rect rect;
  final ui.Color? fill;
  String? label;

  /// A distância entre linhas do pedaço que leva o aviso (dá o tamanho da letra).
  double labelSpace;

  void join(_BandPiece next) {
    rect = rect.expandToInclude(next.rect);
    if (label == null && next.label != null) {
      label = next.label;
      labelSpace = next.space;
    }
  }
}

/// Junta os pedaços de cada sistema e cor em faixas contínuas (as que se tocam
/// viram uma só, com a união dos retângulos), e dá o aviso a uma só por sistema
/// e cor: a primeira faixa contínua, da esquerda para a direita, que tem aviso e
/// cabe. Faixas de sistemas ou de cores diferentes não se juntam; duas faixas do
/// mesmo sistema e cor separadas por um vão ficam como retângulos separados, mas
/// só a da esquerda leva o aviso.
List<ScoreBandRect> _placeLabels(List<_BandPiece> pieces, List<ui.Rect> marks) {
  final byGroup = <(Object, ui.Color?), List<_BandPiece>>{};
  for (final piece in pieces) {
    byGroup.putIfAbsent((piece.group, piece.fill), () => []).add(piece);
  }
  final out = <ScoreBandRect>[];
  for (final group in byGroup.values) {
    group.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    final runs = <_BandRun>[];
    for (final piece in group) {
      if (runs.isNotEmpty && piece.rect.left <= runs.last.rect.right) {
        runs.last.join(piece);
      } else {
        runs.add(_BandRun(piece));
      }
    }
    // O aviso vai à primeira faixa contínua que tem um e cabe; as outras saem
    // sem ele.
    var labelled = false;
    for (final run in runs) {
      final label = run.label;
      final placed = !labelled && label != null
          ? _placedLabel(run, marks)
          : null;
      if (placed == null) {
        out.add(ScoreBandRect(run.rect, fill: run.fill));
        continue;
      }
      labelled = true;
      out.add(
        ScoreBandRect(
          ui.Rect.fromLTRB(
            run.rect.left,
            run.rect.top - scoreBandLabelReserve(placed.labelSize),
            run.rect.right,
            run.rect.bottom,
          ),
          label: label,
          labelSize: placed.labelSize,
          fill: run.fill,
          labelLeft: placed.left,
        ),
      );
    }
  }
  return out;
}

/// O tamanho e a posição do aviso de [run], ou `null` se ele não se desenha (sem
/// folga no topo da página).
({double labelSize, double left})? _placedLabel(
  _BandRun run,
  List<ui.Rect> marks,
) {
  final space = run.labelSpace;
  final fitted = _fittingLabelSize(run.rect.top, space);
  if (fitted == null) return null;
  return (labelSize: fitted, left: _labelLeftOf(run.rect, fitted, marks));
}

/// A largura do aviso, estimada pela letra ([labelSize]): só serve para saber se
/// ele cruza uma caixa de andamento e se cabe na faixa (o texto real é medido na
/// pintura). "você" em negrito fica perto de 2,8 da letra; 3,2 dá uma folga.
double scoreBandLabelWidth(double labelSize) => labelSize * 3.2;

/// A posição em x do aviso de uma faixa de retângulo [rect] (sem a reserva da
/// letra). O texto fica na reserva que a faixa ganha acima de [rect]: do topo da
/// reserva, mais 0,2 da letra, até a borda de cima de [rect]. Cada caixa de
/// andamento que cobre esse trecho empurra o aviso para a direita dela. Não corta
/// o aviso por largura: uma faixa curta deixa o texto passar da borda, como antes.
double _labelLeftOf(ui.Rect rect, double labelSize, List<ui.Rect> marks) {
  final textTop = rect.top - scoreBandLabelReserve(labelSize) + labelSize * 0.2;
  final textBottom = rect.top;
  final width = scoreBandLabelWidth(labelSize);
  var left = rect.left + labelSize * 0.2;
  var moved = true;
  while (moved) {
    moved = false;
    for (final mark in marks) {
      if (mark.right <= left || mark.left >= left + width) continue;
      if (mark.bottom <= textTop || mark.top >= textBottom) continue;
      left = mark.right + labelSize * 0.5;
      moved = true;
    }
  }
  return left;
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

/// O tamanho da letra do aviso: o de sempre (2,5 espaços de pauta), mas, se a
/// folga acima do sistema ([topY], na página, que começa em 0) não comporta a
/// reserva dele (o primeiro sistema da página), a letra encolhe até caber, sem
/// passar de metade do tamanho normal para baixo. Antes o retângulo subia para
/// fora da página e o aviso caía sobre as notas.
double? _fittingLabelSize(double topY, double space) {
  final normal = 2.5 * space;
  if (topY >= scoreBandLabelReserve(normal)) return normal;
  final fits = math.max(topY, 0) / 1.6;
  return fits < 0.6 * space ? null : fits;
}

/// O retângulo de um sistema: da nota mais à esquerda à mais à direita, com uma
/// distância de folga de cada lado. Em cima e embaixo, as pautas que as notas
/// usam (com uma folga), unidas às notas (a linha suplementar sai da pauta).
/// Sem pauta: só as bbox das notas, com folga de metade da altura delas. Com
/// [labelSize], o topo sobe a altura do aviso, que fica dentro da faixa.
ui.Rect _groupRect(_BandGroup group, {required double? labelSize}) {
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
  if (labelSize != null) top -= scoreBandLabelReserve(labelSize);
  return ui.Rect.fromLTRB(left - space, top, right + space, bottom);
}

/// Estado das faixas: as [bands] e o `serial`, que sobe a cada troca. O `serial`
/// existe porque a troca sempre avisou, mesmo com a mesma lista (regra 3 dos
/// motores): o `emit` não pode ignorar essa renotificação.
class ScoreBandState extends Equatable {
  const ScoreBandState({required this.bands, required this.serial});

  final List<ScoreBand> bands;
  final int serial;

  @override
  List<Object?> get props => [serial, bands];
}

/// Cubit das faixas da partitura e suas cores; o `ScorePageView` repinta quando
/// [bands] muda (pelo `BlocRepaint`, que lê o `state` ao pintar).
class ScoreBandCubit extends Cubit<ScoreBandState> {
  ScoreBandCubit({required this.fill, required this.labelColor})
    : super(const ScoreBandState(bands: [], serial: 0));

  /// O fundo da faixa (com a opacidade que o app escolher).
  final ui.Color fill;

  /// A cor do aviso.
  final ui.Color labelColor;

  List<ScoreBand> get bands => state.bands;

  /// Troca as faixas e avisa, mesmo com a mesma lista. Fechado o cubit, a troca
  /// não tem efeito: não há quem pinte, e o `emit` lançaria.
  set bands(List<ScoreBand> value) {
    if (isClosed) return;
    emit(ScoreBandState(bands: value, serial: state.serial + 1));
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
  for (final r in rects) {
    final radius = r.rect.height / 12;
    final paint = ui.Paint()..color = r.fill ?? fill;
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
        r.labelLeft ?? r.rect.left + r.labelSize * 0.2,
        r.rect.top + r.labelSize * 0.2,
      ),
    );
    text.dispose();
  }
}

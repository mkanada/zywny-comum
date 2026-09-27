// Segmentação de uma página por ordem de documento (A01a).
//
// Divide a árvore em segmentos alternados — estático, dinâmico, estático, … —
// **preservando exatamente a ordem de pintura** (§6). É o que torna a cor por
// nota barata sem mudar um pixel: os segmentos estáticos viram `ui.Picture`
// compilados uma vez, e só os dinâmicos repintam quando uma cor muda.
//
// A divisão é por ordem de documento, e não "notas numa camada, resto na
// outra": a partitura é preto sobre branco, então uma sobreposição entre
// elementos da mesma cor é invisível, mas quando a nota fica vermelha ela
// aparece — um feixe desenhado depois da haste tem que continuar depois.
//
// Este arquivo é só lógica (sem `Canvas`): cada item carrega o estado
// herdado no ponto em que aparece, resolvido aqui, para que um segmento
// possa ser pintado isoladamente.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'model.dart';
import 'scene_walk.dart';

/// Transformação afim 2D imutável, na convenção `matrix(a b c d e f)` do SVG:
/// `(x, y) -> (a*x + c*y + e, b*x + d*y + f)`.
///
/// Só `rotate` (§5.1) altera a transformação de um nó, então o que se acumula
/// aqui é a composição dos `rotate` dos ancestrais, no espaço de conteúdo
/// (depois do `translate(origin)` da página, que é da camada e não do item).
class Transform2D {
  const Transform2D(this.a, this.b, this.c, this.d, this.e, this.f);

  /// `rotate(angle, origin)` do SVG: `translate(o) · rotate(angle) ·
  /// translate(-o)`, com [degrees] em graus (a mesma conta do `ScenePainter`).
  factory Transform2D.rotation(double degrees, ui.Offset origin) {
    final radians = degrees * math.pi / 180.0;
    final cosT = math.cos(radians);
    final sinT = math.sin(radians);
    return Transform2D(
      cosT,
      sinT,
      -sinT,
      cosT,
      origin.dx - cosT * origin.dx + sinT * origin.dy,
      origin.dy - sinT * origin.dx - cosT * origin.dy,
    );
  }

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// `this · inner`: aplica [inner] primeiro, depois `this` — a mesma ordem de
  /// pós-multiplicação do `Canvas`, em que um `rotate` aninhado vem depois do
  /// do ancestral.
  Transform2D compose(Transform2D inner) => Transform2D(
    a * inner.a + c * inner.b,
    b * inner.a + d * inner.b,
    a * inner.c + c * inner.d,
    b * inner.c + d * inner.d,
    a * inner.e + c * inner.f + e,
    b * inner.e + d * inner.f + f,
  );

  ui.Offset apply(ui.Offset p) =>
      ui.Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// Matriz 4x4 coluna-major para `Canvas.transform`.
  Float64List toMatrix4() {
    final m = Float64List(16);
    m[0] = a;
    m[1] = b;
    m[4] = c;
    m[5] = d;
    m[10] = 1.0;
    m[12] = e;
    m[13] = f;
    m[15] = 1.0;
    return m;
  }
}

/// Um elemento estático de um segmento: uma forma, um uso de glifo ou um run
/// de texto, com o estado que ele herda no ponto em que aparece.
class StaticItem {
  const StaticItem(this.child, this.inheritedColor, this.transform);

  /// Nunca um [SceneNode]: os grupos estáticos são achatados nas folhas, e os
  /// grupos `hidden` somem (o pintor também não os desenha).
  final SceneChild child;

  /// A cor corrente na folha, depois de aplicar os `color` dos ancestrais.
  final ui.Color inheritedColor;

  /// Composição dos `rotate` dos ancestrais; `null` é a identidade.
  final Transform2D? transform;
}

/// Um nó animável de um segmento dinâmico, com o estado herdado **antes** dele
/// — o `color` e o `rotate` do próprio nó valem dentro do nó, na pintura.
class DynamicItem {
  const DynamicItem(this.node, this.inheritedColor, this.transform);

  final SceneNode node;

  /// A cor corrente no pai do nó.
  final ui.Color inheritedColor;

  /// Composição dos `rotate` dos ancestrais (sem o do próprio nó); `null` é a
  /// identidade.
  final Transform2D? transform;
}

/// Um trecho contíguo da ordem de pintura de uma página.
sealed class PageSegment {
  const PageSegment();
}

/// Elementos que nunca mudam de cor, em ordem de documento.
class StaticSegment extends PageSegment {
  const StaticSegment(this.items);

  final List<StaticItem> items;
}

/// Nós animáveis consecutivos na ordem de documento, fundidos num só segmento.
class DynamicSegment extends PageSegment {
  const DynamicSegment(this.items);

  final List<DynamicItem> items;

  List<SceneNode> get nodes => [for (final item in items) item.node];
}

/// Contagens de uma segmentação, para a instrumentação de A01c.
extension PageSegmentStats on List<PageSegment> {
  int get segmentCount => length;

  int get staticSegmentCount => whereType<StaticSegment>().length;

  int get dynamicSegmentCount => whereType<DynamicSegment>().length;

  /// Folhas estáticas somadas de todos os segmentos estáticos.
  int get staticItemCount => whereType<StaticSegment>().fold(
    0,
    (total, segment) => total + segment.items.length,
  );

  /// Nós animáveis somados de todos os segmentos dinâmicos.
  int get dynamicNodeCount => whereType<DynamicSegment>().fold(
    0,
    (total, segment) => total + segment.items.length,
  );
}

/// Ids animáveis padrão de um documento: os que aparecem em `on`/`off` do
/// timemap. `restsOn`/`restsOff` ficam de fora (pausas não acendem).
///
/// Com [document], cada id é resolvido pela regra do sufixo (E02a) antes de
/// entrar no conjunto: um id expandido (`-rend2`) sem a base solta em
/// `on`/`off` torna a base dinâmica do mesmo jeito, senão ela ficaria presa
/// num `ui.Picture` estático e nunca mudaria de cor. Sem [document] (ou um id
/// que não resolve a nada — repetições que nem a base têm no timemap, hoje
/// raro no corpus), o id original entra como está, e [segmentPage] o ignora.
Set<String> animatableIdsFromTimemap(
  List<TimemapEntry>? timemap, {
  VsbDocument? document,
}) {
  final ids = <String>{};
  for (final entry in timemap ?? const <TimemapEntry>[]) {
    for (final id in entry.on) {
      ids.add(document?.sceneIdOf(id) ?? id);
    }
    for (final id in entry.off) {
      ids.add(document?.sceneIdOf(id) ?? id);
    }
  }
  return ids;
}

/// Divide a página em segmentos alternados estático/dinâmico na ordem de
/// pintura (§6).
///
/// Um nó cujo `id` está em [animatableIds] é dinâmico e entra **inteiro** num
/// segmento dinâmico: não se desce nele procurando outro dentro. Ids de
/// [animatableIds] que não existem na página são ignorados — com
/// [animatableIdsFromTimemap] chamado com `document:` (E02a), isso já não
/// acontece com um id expandido (`-rend2`) cuja base existe na página; sobra
/// só para um id que não resolve a nada na cena. Nós dinâmicos consecutivos
/// na ordem de documento se fundem num só segmento — é isso que mantém o número de
/// `ui.Picture` por página na casa da centena, e não do milhar. Nunca há
/// segmento vazio, e [animatableIds] vazio dá um só segmento estático.
///
/// O percurso é o de [walkScene], o mesmo do `ScenePainter`.
List<PageSegment> segmentPage(ScenePage page, Set<String> animatableIds) {
  final segmenter = _Segmenter(animatableIds);
  walkScene(page.root, const ui.Color(0xFF000000), segmenter);
  return segmenter.finish();
}

class _Segmenter implements SceneVisitor {
  _Segmenter(this._animatableIds);

  final Set<String> _animatableIds;
  final List<PageSegment> _segments = [];

  // Segmento aberto: exatamente um dos dois é não nulo, ou nenhum.
  List<StaticItem>? _openStatic;
  List<DynamicItem>? _openDynamic;

  // Transformação corrente; empilhada por `enterGroup`, desempilhada por
  // `exitGroup`. Só cresce com `rotate`, então a identidade (`null`) é o caso
  // comum e não aloca nada.
  final List<Transform2D?> _transforms = [null];

  @override
  bool enterGroup(SceneNode node, ui.Color inheritedColor, ui.Color color) {
    final id = node.id;
    if (id != null && _animatableIds.contains(id)) {
      _addDynamic(DynamicItem(node, inheritedColor, _transforms.last));
      return false;
    }
    final rotate = node.rotate;
    final parent = _transforms.last;
    if (rotate == null) {
      _transforms.add(parent);
    } else {
      final own = Transform2D.rotation(rotate.angle, rotate.origin);
      _transforms.add(parent == null ? own : parent.compose(own));
    }
    return true;
  }

  @override
  void visitLeaf(SceneChild leaf, ui.Color color) {
    _addStatic(StaticItem(leaf, color, _transforms.last));
  }

  @override
  void exitGroup(SceneNode node) {
    _transforms.removeLast();
  }

  void _addStatic(StaticItem item) {
    var open = _openStatic;
    if (open == null) {
      _closeOpen();
      open = _openStatic = [];
    }
    open.add(item);
  }

  void _addDynamic(DynamicItem item) {
    var open = _openDynamic;
    if (open == null) {
      _closeOpen();
      open = _openDynamic = [];
    }
    open.add(item);
  }

  void _closeOpen() {
    final staticItems = _openStatic;
    if (staticItems != null) {
      _segments.add(StaticSegment(staticItems));
      _openStatic = null;
    }
    final dynamicItems = _openDynamic;
    if (dynamicItems != null) {
      _segments.add(DynamicSegment(dynamicItems));
      _openDynamic = null;
    }
  }

  List<PageSegment> finish() {
    _closeOpen();
    return _segments;
  }
}

// Percurso único da árvore de uma página (§6), parametrizado por um visitante.
//
// A ordem de pintura e a resolução da cor herdada existem num lugar só. O
// `ScenePainter` (R02b) e a segmentação (A01a) são visitantes: se cada um
// tivesse o próprio percurso, os dois divergiriam — e a garantia de que
// segmentar não muda um pixel deixaria de valer.
library;

import 'dart:ui' as ui;

import 'model.dart';

/// Visitante do percurso de [walkScene].
///
/// Os eventos chegam em ordem de documento (o último filho pinta por cima).
/// Nós `hidden` (e toda a subárvore) nunca são visitados.
abstract interface class SceneVisitor {
  /// Entrada num grupo não `hidden`.
  ///
  /// [inheritedColor] é a cor corrente **antes** deste nó; [color] é a que vale
  /// para os filhos, depois de aplicar `node.color` (e o override por `id`, se
  /// houver). Devolver `false` pula os filhos — e [exitGroup] não é chamado
  /// para este nó.
  bool enterGroup(SceneNode node, ui.Color inheritedColor, ui.Color color);

  /// Um filho que não é grupo (forma, uso de glifo ou run de texto), com a
  /// cor corrente que ele herda.
  void visitLeaf(SceneChild leaf, ui.Color color);

  /// Saída de um grupo cujo [enterGroup] devolveu `true`, depois dos filhos.
  void exitGroup(SceneNode node);
}

/// Percorre a árvore a partir de [root] em profundidade, na ordem de
/// `children`, mantendo a cor corrente (§6).
///
/// [initialColor] é a cor herdada por [root] (o preto do
/// `<svg class="definition-scale">` para uma página inteira).
/// [colorOverrides] troca a cor de um nó por `id` e vence o `color` do
/// próprio nó; o que é herdado pelos filhos é a cor trocada.
void walkScene(
  SceneNode root,
  ui.Color initialColor,
  SceneVisitor visitor, {
  Map<String, ui.Color> colorOverrides = const {},
}) {
  _walkNode(root, initialColor, visitor, colorOverrides);
}

void _walkNode(
  SceneNode node,
  ui.Color current,
  SceneVisitor visitor,
  Map<String, ui.Color> colorOverrides,
) {
  if (node.hidden) {
    return;
  }
  // Uma conversão `#rrggbb` -> `Color` por nó, não por forma.
  ui.Color color = current;
  final override = node.id == null ? null : colorOverrides[node.id];
  if (override != null) {
    color = override;
  } else if (node.color != null) {
    color = parseCssColor(node.color!);
  }
  if (!visitor.enterGroup(node, current, color)) {
    return;
  }
  for (final child in node.children) {
    switch (child) {
      case SceneNode():
        _walkNode(child, color, visitor, colorOverrides);
      case SceneShape() || SceneText():
        visitor.visitLeaf(child, color);
    }
  }
  visitor.exitGroup(node);
}

/// Converte `#rrggbb` (minúsculo, conforme §7) em [ui.Color] opaca.
ui.Color parseCssColor(String hex) {
  return ui.Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

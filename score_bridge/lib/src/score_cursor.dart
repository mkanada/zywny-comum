// `ScoreCursor` (A04b): um retângulo/barra pronto para pôr sobre um elemento.
//
// É um widget comum, desenhado por um `overlayBuilder`; a posição vem de
// `ScoreGeometry.rectForId` a cada layout (nada de pixel memorizado), então
// acompanha redimensionamento, virada por haste e rolagem:
//
//   ScoreView(
//     overlayIds: [currentNoteId],
//     overlayBuilder: ScoreCursor.builder(color: Colors.red),
//   )
//
// O overlay é uma camada de widget **acima** de toda a partitura: não
// participa da ordem de pintura da cena e ignora toques.
library;

import 'package:flutter/widgets.dart';

class ScoreCursor extends StatelessWidget {
  const ScoreCursor({
    super.key,
    this.color = const Color(0xFFD32F2F),
    this.thickness = 2,
    this.fill = false,
    this.fillOpacity = 0.2,
  });

  /// Cor da borda (e do preenchimento, se [fill]).
  final Color color;

  /// Espessura da borda em pixels lógicos; `0` desenha só o preenchimento.
  final double thickness;

  /// Preenche o retângulo com [color] a [fillOpacity].
  final bool fill;
  final double fillOpacity;

  /// Um `overlayBuilder` que desenha um cursor sobre cada id, com estes
  /// parâmetros.
  static Widget? Function(BuildContext, String, Rect) builder({
    Color color = const Color(0xFFD32F2F),
    double thickness = 2,
    bool fill = false,
    double fillOpacity = 0.2,
  }) =>
      (context, id, rect) => ScoreCursor(
        color: color,
        thickness: thickness,
        fill: fill,
        fillOpacity: fillOpacity,
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill ? color.withValues(alpha: fillOpacity) : null,
          border: thickness > 0
              ? Border.all(color: color, width: thickness)
              : null,
        ),
      ),
    );
  }
}

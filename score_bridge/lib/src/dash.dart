// Tracejado sobre `ui.Path` (R02c).
//
// O Flutter não tem traço tracejado nativo. Este utilitário aplica o `dash`
// do formato (§5.2: `[dashLength, gapLength]`) alternando segmentos de traço
// e intervalo com `PathMetric.extractPath`, por contorno (cada contorno
// recomeça com a fase no traço — é o que o `resvg` faz por subpath no SVG e
// o que o corpus precisa: os 8 casos são retas de um contorno só).
//
// Só o traço é tracejado; o preenchimento usa sempre o caminho original
// (é a semântica do SVG: `stroke-dasharray` não afeta `fill`).
library;

import 'dart:ui' as ui;

import 'model.dart';

/// Aplica o tracejado [dash] a [source], devolvendo um caminho novo só com
/// os segmentos "acesos".
///
/// Cada contorno de [source] recomeça com traço na distância 0. Se
/// `length <= 0` ou `gap <= 0`, devolve [source] sem copiar (não há caso
/// real no corpus: os 8 `dash` são todos `[36, 72]`).
ui.Path applyDash(ui.Path source, SceneDash dash) {
  if (dash.length <= 0 || dash.gap <= 0) {
    return source;
  }
  final dest = ui.Path();
  for (final metric in source.computeMetrics()) {
    var dist = 0.0;
    var draw = true;
    while (dist < metric.length) {
      final segLen = draw ? dash.length : dash.gap;
      var end = dist + segLen;
      if (end > metric.length) {
        end = metric.length;
      }
      if (draw) {
        dest.addPath(metric.extractPath(dist, end), ui.Offset.zero);
      }
      dist = end;
      draw = !draw;
    }
  }
  return dest;
}

/// Soma dos comprimentos de todos os contornos de [path].
double totalPathLength(ui.Path path) {
  var total = 0.0;
  for (final metric in path.computeMetrics()) {
    total += metric.length;
  }
  return total;
}

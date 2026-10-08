// Oráculo da regra da haste (cabeçalho de `score_timeline.dart`) para os
// testes com documentos reais: calcula, por fora do `ScoreTimeline`, quando
// a conclusão da haste de um compasso tem de começar.
import 'dart:math' as math;

import 'package:score_bridge/score_bridge.dart';

/// Instante da última nota ou pausa de [m] no timemap de [doc].
double lastEventMs(VsbDocument doc, MeasureInfo m) {
  var last = m.startMs.toDouble();
  for (final e in doc.timemap!) {
    if (e.tstamp >= m.startMs &&
        e.tstamp < m.endMs &&
        (e.on.isNotEmpty || e.restsOn.isNotEmpty)) {
      last = math.max(last, e.tstamp);
    }
  }
  return last;
}

/// `C = max(M.start + D, L − out*·D)`: [fromX] é o `xInício` da conclusão,
/// [endX] o fim da haste e [revealX] a borda a partir da qual o 1º compasso
/// da página nova está inteiro à vista (fim dele + largura da haste).
double concStart({
  required MeasureInfo m,
  required double d,
  required double lastMs,
  required double fromX,
  required double endX,
  required double revealX,
}) {
  final shown = ((revealX - fromX) / (endX - fromX)).clamp(0.0, 1.0);
  final out = math.max(kRevealBlurClearAt, shown);
  return math.max(m.startMs + d, lastMs - out * d);
}

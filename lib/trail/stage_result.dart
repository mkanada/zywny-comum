// J02 — Regra de aprovação da etapa da trilha.
// R04: `StageResult` e `WaitTally` são da prática; aqui fica só os 90%.
library;

import '../practice/stage_result.dart';

export '../practice/stage_result.dart';

/// Aproveitamento mínimo da trilha: 90%, fixo (J00).
const double kTrailPassAccuracy = 0.90;

extension StagePass on StageResult {
  bool get passed =>
      nothingToPlay || (total > 0 && hits / total >= kTrailPassAccuracy);
}

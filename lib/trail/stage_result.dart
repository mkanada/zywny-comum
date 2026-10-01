// J02 — Resultado da etapa e contagem do modo espera (Dart puro).
library;

import '../practice/practice_report.dart';

/// Aproveitamento mínimo da trilha: 90%, fixo (J00).
const double kTrailPassAccuracy = 0.90;

/// Resultado de uma passagem de etapa: acertos, total avaliado e compassos
/// (ocorrências em `ScoreTimeline.measures`) com erro.
class StageResult {
  const StageResult({
    required this.hits,
    required this.total,
    required this.badMeasures,
  });

  final int hits;
  final int total;

  /// Ocorrências com algum erro ou imprecisão.
  final Set<int> badMeasures;

  double get accuracy => total == 0 ? 0 : hits / total;

  /// Porcentagem inteira, arredondada para baixo: 89,9% não vira 90.
  /// Conta inteira (`~/`) para 90% cravar 90 sem erro de binário.
  int get percent => total == 0 ? 0 : (hits * 100 ~/ total);

  bool get passed =>
      total > 0 && hits / total >= kTrailPassAccuracy;

  /// Do resumo pronto das sessões. No ritmo, `extra` (toque sem alvo) entra
  /// no denominador: sem isso, bater teclas sem parar aprovaria (J00).
  factory StageResult.fromReport(
    PracticeReport report, {
    required bool rhythm,
  }) {
    final total = report.total + (rhythm ? report.extra : 0);
    final bad = <int>{
      for (final m in report.measures)
        if (m.errors + m.imprecise > 0) m.index,
    };
    return StageResult(
      hits: report.correct,
      total: total,
      badMeasures: bad,
    );
  }
}

/// Contador do modo espera: "de primeira" = nenhum `wrong` enquanto o passo
/// estava pendente. Um acorde é um passo só.
class WaitTally {
  int? _current;
  final Map<int, bool> _hadWrong = {};
  final Map<int, int> _measureOf = {};
  int _done = 0;
  int _firstTry = 0;
  final Set<int> _bad = {};

  /// Um passo ficou pendente (`WaitModeSession.current`).
  void stepStarted(int stepIndex, int measure) {
    _current = stepIndex;
    _measureOf[stepIndex] = measure;
    _hadWrong.putIfAbsent(stepIndex, () => false);
  }

  /// Uma tecla errada enquanto havia passo pendente. Antes do primeiro
  /// `stepStarted` ou depois do último `stepDone`, sem passo pendente, é
  /// ignorado.
  void wrong() {
    final current = _current;
    if (current == null) return;
    _hadWrong[current] = true;
  }

  /// O passo pendente concluiu (avançou).
  void stepDone() {
    final current = _current;
    if (current == null) return;
    _done++;
    if (_hadWrong[current] ?? false) {
      _bad.add(_measureOf[current]!);
    } else {
      _firstTry++;
    }
    _current = null;
  }

  StageResult result() =>
      StageResult(hits: _firstTry, total: _done, badMeasures: Set.of(_bad));
}

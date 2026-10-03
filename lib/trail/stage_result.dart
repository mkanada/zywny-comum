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
    this.nothingToPlay = false,
  });

  final int hits;
  final int total;

  /// A mão do aluno não tem nota nenhuma neste trecho (só pausa ou nota
  /// ligada de antes): não há o que errar, a etapa conta como cumprida.
  final bool nothingToPlay;

  /// Ocorrências com algum erro ou imprecisão.
  final Set<int> badMeasures;

  double get accuracy => nothingToPlay ? 1 : (total == 0 ? 0 : hits / total);

  /// Porcentagem inteira, arredondada para baixo: 89,9% não vira 90.
  /// Conta inteira (`~/`) para 90% cravar 90 sem erro de binário.
  int get percent =>
      nothingToPlay ? 100 : (total == 0 ? 0 : (hits * 100 ~/ total));

  bool get passed =>
      nothingToPlay || (total > 0 && hits / total >= kTrailPassAccuracy);

  /// Do resumo pronto das sessões.
  factory StageResult.fromReport(PracticeReport report) {
    final total = report.total;
    final bad = <int>{
      for (final m in report.measures)
        if (m.errors + m.imprecise > 0) m.index,
    };
    return StageResult(hits: report.correct, total: total, badMeasures: bad);
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

  /// Passos concluídos de primeira e passos concluídos (o `hits`/`total` de
  /// [result], sem montar o resultado).
  int get firstTry => _firstTry;
  int get done => _done;

  StageResult result() =>
      StageResult(hits: _firstTry, total: _done, badMeasures: Set.of(_bad));
}

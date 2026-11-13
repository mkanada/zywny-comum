// J02 — Resultado da etapa e contagem do modo espera (Dart puro).
library;

import 'practice_report.dart';

/// Resultado de uma passagem de etapa: acertos, total avaliado e compassos
/// (ocorrências em `ScoreTimeline.measures`) com erro.
class StageResult {
  const StageResult({
    required this.hits,
    required this.total,
    required this.badMeasures,
    this.nothingToPlay = false,
    this.rewinds = const {},
  });

  final int hits;
  final int total;

  /// A mão do aluno não tem nota nenhuma neste trecho (só pausa ou nota
  /// ligada de antes): não há o que errar, a etapa conta como cumprida.
  final bool nothingToPlay;

  /// Ocorrências com algum erro ou imprecisão.
  final Set<int> badMeasures;

  /// A volta na hora (LP24.2): quantas vezes cada ocorrência voltou porque
  /// saiu com erro. Vazio sem volta (ou com a volta desligada). Os erros das
  /// tentativas que voltaram continuam no resultado.
  final Map<int, int> rewinds;

  /// O mesmo resultado, com [rewinds].
  StageResult withRewinds(Map<int, int> rewinds) => StageResult(
    hits: hits,
    total: total,
    badMeasures: badMeasures,
    nothingToPlay: nothingToPlay,
    rewinds: rewinds,
  );

  double get accuracy => nothingToPlay ? 1 : (total == 0 ? 0 : hits / total);

  /// Porcentagem inteira, arredondada para baixo: 89,9% não vira 90.
  /// Conta inteira (`~/`) para 90% cravar 90 sem erro de binário.
  int get percent =>
      nothingToPlay ? 100 : (total == 0 ? 0 : (hits * 100 ~/ total));

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
  final List<bool> _results = [];

  /// Um passo ficou pendente (`WaitModeSession.current`).
  void stepStarted(int stepIndex, int measure) {
    _current = stepIndex;
    _measureOf[stepIndex] = measure;
    _hadWrong.putIfAbsent(stepIndex, () => false);
  }

  /// A volta na hora (LP24.2): os passos do compasso [measure] em diante vão
  /// ser tocados de novo e começam sem a tecla errada da tentativa que voltou.
  /// O que já foi contado (concluídos, de primeira, compassos com erro) fica.
  void rewindTo(int measure) {
    for (final entry in _measureOf.entries) {
      if (entry.value >= measure) _hadWrong.remove(entry.key);
    }
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
    _results.add(!(_hadWrong[current] ?? false));
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

  /// Para cada passo concluído, na ordem em que concluíram, se saiu de primeira.
  List<bool> get steps => List.unmodifiable(_results);

  StageResult result() =>
      StageResult(hits: _firstTry, total: _done, badMeasures: Set.of(_bad));
}

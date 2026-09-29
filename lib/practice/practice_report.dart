// T03: resumo de uma sessão de tempo real — Dart puro, sem UI. Agrega os
// vereditos por compasso **ocorrência** (índice em `ScoreTimeline.measures`,
// ordem de execução): um compasso repetido tem uma linha por volta, com
// `pass` para a UI dizer "2ª vez"; o número mostrado é `index + 1`, o mesmo
// do "ir para o compasso".
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'practice_session.dart';
import 'rhythm_session.dart';

/// Um veredito e o compasso (ocorrência) onde ele caiu.
@immutable
class ReportEntry {
  const ReportEntry(this.verdict, this.measureIndex, {this.pass = 1});

  final NoteVerdict verdict;
  final int measureIndex;
  final int pass;
}

@immutable
class MeasureStats {
  const MeasureStats({
    required this.index,
    required this.pass,
    this.correct = 0,
    this.early = 0,
    this.late = 0,
    this.wrong = 0,
    this.missed = 0,
  });

  final int index;
  final int pass;
  final int correct;
  final int early;
  final int late;
  final int wrong;
  final int missed;

  int get total => correct + early + late + wrong + missed;

  /// Erros de verdade: nota errada ou perdida. Adiantado/atrasado é
  /// imprecisão, conta à parte.
  int get errors => wrong + missed;
  int get imprecise => early + late;

  MeasureStats _add(PracticeVerdictKind kind) => MeasureStats(
    index: index,
    pass: pass,
    correct: correct + (kind == PracticeVerdictKind.correct ? 1 : 0),
    early: early + (kind == PracticeVerdictKind.early ? 1 : 0),
    late: late + (kind == PracticeVerdictKind.late ? 1 : 0),
    wrong: wrong + (kind == PracticeVerdictKind.wrong ? 1 : 0),
    missed: missed + (kind == PracticeVerdictKind.missed ? 1 : 0),
  );
}

/// Um veredito de ritmo (T05) e o compasso (ocorrência) onde caiu. Os
/// `extra` não têm compasso próprio e só entram na contagem.
@immutable
class RhythmReportEntry {
  const RhythmReportEntry(this.verdict, this.measureIndex, {this.pass = 1});

  final RhythmVerdict verdict;
  final int measureIndex;
  final int pass;
}

class PracticeReport {
  /// Resumo do treino de rítmica (T05): um onset é um veredito; `extra`
  /// (toque sem alvo) conta em [extra] e não entra em [total]/[accuracy]. O
  /// [meanDeltaMs] é a tendência (negativo = corre) e [stdDevMs] a
  /// regularidade.
  factory PracticeReport.rhythm(
    Iterable<RhythmReportEntry> entries, {
    double speed = 1,
  }) {
    var extra = 0;
    final mapped = <ReportEntry>[];
    for (final e in entries) {
      final v = e.verdict;
      if (v.kind == RhythmVerdictKind.extra) {
        extra++;
        continue;
      }
      mapped.add(
        ReportEntry(
          NoteVerdict(
            eventId: v.eventIds.isEmpty ? null : v.eventIds.first,
            pitch: 0,
            kind: switch (v.kind) {
              RhythmVerdictKind.correct => PracticeVerdictKind.correct,
              RhythmVerdictKind.early => PracticeVerdictKind.early,
              RhythmVerdictKind.late => PracticeVerdictKind.late,
              _ => PracticeVerdictKind.missed,
            },
            deltaMs: v.deltaMs,
            velocity: v.velocity,
          ),
          e.measureIndex,
          pass: e.pass,
        ),
      );
    }
    return PracticeReport(mapped, speed: speed, extra: extra);
  }

  /// [speed]: andamento da sessão — os `deltaMs` do tempo real são musicais,
  /// e o resumo mostra ms de parede (o que o aluno sente).
  factory PracticeReport(
    Iterable<ReportEntry> entries, {
    double speed = 1,
    int extra = 0,
  }) {
    final byMeasure = <int, MeasureStats>{};
    var correct = 0, early = 0, late = 0, wrong = 0, missed = 0;
    var deltaSum = 0.0, deltaAbsSum = 0.0, deltaCount = 0;
    final walls = <double>[];
    for (final e in entries) {
      final v = e.verdict;
      byMeasure[e.measureIndex] =
          (byMeasure[e.measureIndex] ??
                  MeasureStats(index: e.measureIndex, pass: e.pass))
              ._add(v.kind);
      switch (v.kind) {
        case PracticeVerdictKind.correct:
          correct++;
        case PracticeVerdictKind.early:
          early++;
        case PracticeVerdictKind.late:
          late++;
        case PracticeVerdictKind.wrong:
          wrong++;
        case PracticeVerdictKind.missed:
          missed++;
      }
      if (v.kind == PracticeVerdictKind.correct ||
          v.kind == PracticeVerdictKind.early ||
          v.kind == PracticeVerdictKind.late) {
        final wall = v.deltaMs / speed;
        deltaSum += wall;
        deltaAbsSum += wall.abs();
        deltaCount++;
        walls.add(wall);
      }
    }
    final measures = byMeasure.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final mean = deltaCount == 0 ? 0.0 : deltaSum / deltaCount;
    var sq = 0.0;
    for (final w in walls) {
      sq += (w - mean) * (w - mean);
    }
    return PracticeReport._(
      extra: extra,
      stdDevMs: deltaCount == 0 ? 0 : math.sqrt(sq / deltaCount),
      correct: correct,
      early: early,
      late: late,
      wrong: wrong,
      missed: missed,
      meanDeltaMs: deltaCount == 0 ? 0 : deltaSum / deltaCount,
      meanAbsDeltaMs: deltaCount == 0 ? 0 : deltaAbsSum / deltaCount,
      measures: measures,
    );
  }

  const PracticeReport._({
    required this.extra,
    required this.stdDevMs,
    required this.correct,
    required this.early,
    required this.late,
    required this.wrong,
    required this.missed,
    required this.meanDeltaMs,
    required this.meanAbsDeltaMs,
    required this.measures,
  });

  final int correct;
  final int early;
  final int late;
  final int wrong;
  final int missed;

  /// Toques sem alvo (só no modo ritmo); fora de [total].
  final int extra;

  /// Desvio-padrão do delta nas notas casadas, ms de parede — regularidade
  /// (quanto menor, mais constante).
  final double stdDevMs;

  /// Média de (tocada − esperada) nas notas casadas, em ms de parede:
  /// negativo = adiantado, positivo = atrasado.
  final double meanDeltaMs;

  /// Média do desvio absoluto, ms de parede.
  final double meanAbsDeltaMs;

  /// Compassos (ocorrências) com algum veredito, em ordem.
  final List<MeasureStats> measures;

  int get total => correct + early + late + wrong + missed;
  bool get isEmpty => total == 0;

  /// Precisão: notas no tempo certo sobre todos os vereditos (0..1).
  double get accuracy => total == 0 ? 0 : correct / total;

  /// Compassos com mais erros (errada/perdida primeiro, imprecisão desempata),
  /// só os que têm algum erro ou imprecisão; no máximo [max].
  List<MeasureStats> worstMeasures({int max = 3}) {
    final bad = measures.where((m) => m.errors + m.imprecise > 0).toList()
      ..sort((a, b) {
        final byErrors = b.errors.compareTo(a.errors);
        if (byErrors != 0) return byErrors;
        final byImprecise = b.imprecise.compareTo(a.imprecise);
        return byImprecise != 0 ? byImprecise : a.index.compareTo(b.index);
      });
    return bad.take(max).toList();
  }
}

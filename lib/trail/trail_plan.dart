// J03 — Plano da trilha: quais etapas existem para uma música (trechos +
// fase final), pulando as fases de mão vazia.
library;

import 'package:score_bridge/score_bridge.dart' show MeasureInfo;

import '../music/performance_track.dart';
import '../practice/practice_controller.dart' show PracticeMode;
import 'trail_path.dart';
import 'trail_segments.dart';
import 'trail_stage.dart';

/// N efetivo da música: o dela, senão o geral (J00).
int effectiveTrailMeasures({required int general, int? hymn}) =>
    hymn ?? general;

/// Vãos (`startMs`, `endMs`) dentro da etapa (J08): os saltos do caminho entre
/// seus compassos lógicos. O agendador os pula e as sessões nem os avaliam.
/// Vazio sem saltos.
List<({double startMs, double endMs})> trailStageGaps(
  TrailPath path,
  TrailStage stage,
) {
  final gaps = <({double startMs, double endMs})>[];
  for (final jump in path.jumps) {
    if (jump > stage.first && jump <= stage.last) {
      gaps.add((
        startMs: path.logical[jump - 1].endMs,
        endMs: path.logical[jump].startMs,
      ));
    }
  }
  return gaps;
}

/// Ids (na cena) dos compassos do trecho da [stage], na ordem do caminho —
/// o que a pauta marca com a etapa parada (U02). Vazio na fase final
/// (`segment == null`: a música inteira, nada a marcar). Um id repetido por
/// ocorrências (casas, ritornelos) aparece uma vez.
List<String> trailStageMeasureIds(
  TrailPath path,
  TrailStage stage,
  List<MeasureInfo> measures,
) {
  if (stage.segment == null) return const [];
  final ids = <String>{};
  for (var i = stage.first; i <= stage.last; i++) {
    for (final m in path.logical[i].measures) {
      ids.add(measures[m.occurrence].id);
    }
  }
  return ids.toList();
}

/// Lista ordenada de etapas: trecho 0 inteiro, trecho 1…, fase final.
class TrailPlan {
  const TrailPlan({required this.n, required this.stages});

  /// O N com que o corte foi feito — o progresso guardado com outro N é de
  /// outro corte e é tratado como vazio (a tela confirma antes de trocar).
  final int n;
  final List<TrailStage> stages;

  bool get isEmpty => stages.isEmpty;

  /// Trechos distintos no plano (etapas com `segment`).
  int get segmentCount {
    var count = 0;
    for (final s in stages) {
      final seg = s.segment;
      if (seg != null && seg + 1 > count) count = seg + 1;
    }
    return count;
  }

  static TrailPlan build(
    TrailPath path,
    PerformanceTrack track, {
    required int n,
    bool includeFinal = true,
  }) {
    final segments = cutSegments(path, n);
    if (segments.isEmpty) return TrailPlan(n: n, stages: const []);
    final stages = <TrailStage>[];
    for (final seg in segments) {
      final right = _hasNotes(track, seg.startMs, seg.endMs, const {1});
      final left = _hasNotes(track, seg.startMs, seg.endMs, const {2});
      // Sem nota nenhuma no trecho (pausa): sem etapas — o desbloqueio
      // linear simplesmente o atravessa.
      if (!right && !left) continue;
      final both = right && left;
      final phases = <TrailPhase>[
        if (right) TrailPhase.notasD,
        if (left) TrailPhase.notasE,
        if (both) TrailPhase.notasJ,
        if (right) TrailPhase.ritmoD,
        if (left) TrailPhase.ritmoE,
        if (both) TrailPhase.junto,
      ];
      for (final phase in phases) {
        if (phase.mode == PracticeMode.wait) {
          stages.add(
            TrailStage(
              id: 't${seg.index}.${phase.name}',
              segment: seg.index,
              phase: phase,
              speed: null,
              startMs: seg.startMs,
              endMs: seg.endMs,
              label: trailStageLabel(phase, null),
              first: seg.first,
              last: seg.last,
            ),
          );
        } else {
          for (final speed in kTrailSpeeds) {
            final pct = (speed * 100).round();
            stages.add(
              TrailStage(
                id: 't${seg.index}.${phase.name}.$pct',
                segment: seg.index,
                phase: phase,
                speed: speed,
                startMs: seg.startMs,
                endMs: seg.endMs,
                label: trailStageLabel(phase, speed),
                first: seg.first,
                last: seg.last,
              ),
            );
          }
        }
      }
    }
    final startMs = path.logical.first.startMs;
    final endMs = path.logical.last.endMs;
    // A fase final é do J07: o J05 monta o plano só com os trechos e mostra
    // "fase final em breve" ao acabar o último.
    if (includeFinal) {
      for (final speed in kTrailSpeeds) {
        final pct = (speed * 100).round();
        stages.add(
          TrailStage(
            id: 'final.$pct',
            segment: null,
            phase: TrailPhase.junto,
            speed: speed,
            startMs: startMs,
            endMs: endMs,
            label: trailStageLabel(TrailPhase.junto, speed),
            first: 0,
            last: path.measureCount - 1,
          ),
        );
      }
    }
    return TrailPlan(n: n, stages: stages);
  }
}

/// Há evento não-ornamento da pauta em `[startMs, endMs)` (J00/J03).
bool _hasNotes(
  PerformanceTrack track,
  double startMs,
  double endMs,
  Set<int> staves,
) {
  for (final e in track.events) {
    if (e.onMs >= endMs - kRangeBoundaryToleranceMs) break;
    if (e.onMs >= startMs - kRangeBoundaryToleranceMs &&
        staves.contains(e.staff) &&
        !e.ornament) {
      return true;
    }
  }
  return false;
}

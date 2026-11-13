// J03 — Plano da trilha: quais etapas existem para uma música (trechos +
// fase final), pulando as fases de mão vazia.
library;

import 'package:score_bridge/score_bridge.dart' show MeasureInfo;

import 'package:zywny_audio/performance_track.dart';

import '../practice/hand.dart';
import '../practice/practice_controller.dart' show PracticeMode;
import 'trail_path.dart';
import 'trail_segments.dart';
import 'trail_stage.dart';

/// N efetivo da música: o dela, senão o geral (J00).
int effectiveTrailMeasures({required int general, int? piece}) =>
    piece ?? general;

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
/// O que muda a montagem de um plano de trilha (ver [TrailPlan.build]).
class TrailPlanOptions {
  const TrailPlanOptions({this.includeFinal = true, this.phases, this.speeds});

  /// Se a fase final (J07) entra no plano, depois dos trechos.
  final bool includeFinal;

  /// As fases escolhidas; `null` são todas.
  final List<TrailPhase>? phases;

  /// Os andamentos escolhidos; `null` são todos.
  final Set<double>? speeds;
}

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

  /// [phases]/[speeds]: as etapas (na ordem em que entram em cada trecho)
  /// e os andamentos que o aluno escolheu nas configurações (`null`: todas,
  /// na ordem de [TrailPhase]). Os ids não mudam com a escolha, então o
  /// progresso das etapas que ficam continua valendo. A fase final não é
  /// filtrada.
  static TrailPlan build(
    TrailPath path,
    PerformanceTrack track, {
    required int n,
    TrailPlanOptions options = const TrailPlanOptions(),
  }) {
    final phases = options.phases;
    final speeds = options.speeds;
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
      // Cada etapa só onde a(s) mão(s) dela têm nota no trecho.
      bool fits(TrailPhase p) => switch (p.hand) {
        Hand.direita => right,
        Hand.esquerda => left,
        Hand.ambas => both,
      };
      stages.addAll(
        _segmentStages(seg, (phases ?? TrailPhase.values).where(fits), speeds),
      );
    }
    // A fase final é do J07: o J05 monta o plano só com os trechos e mostra
    // "fase final em breve" ao acabar o último.
    if (options.includeFinal) stages.addAll(_finalStages(path));
    return TrailPlan(n: n, stages: stages);
  }

  /// As etapas de um trecho, nas [phases] que cabem nele: uma por fase no modo
  /// espera, e uma por andamento (dos [speeds] escolhidos) nas com tempo.
  static List<TrailStage> _segmentStages(
    TrailSegment seg,
    Iterable<TrailPhase> phases,
    Set<double>? speeds,
  ) {
    final out = <TrailStage>[];
    for (final phase in phases) {
      if (phase.mode == PracticeMode.wait) {
        out.add(
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
        continue;
      }
      for (final speed in kTrailSpeeds) {
        if (speeds != null && !speeds.contains(speed)) continue;
        final pct = (speed * 100).round();
        out.add(
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
    return out;
  }

  /// A fase final (J07): uma etapa por andamento, sobre a música inteira.
  static List<TrailStage> _finalStages(TrailPath path) {
    final startMs = path.logical.first.startMs;
    final endMs = path.logical.last.endMs;
    return [
      for (final speed in kTrailSpeeds)
        TrailStage(
          id: 'final.${(speed * 100).round()}',
          segment: null,
          phase: TrailPhase.junto,
          speed: speed,
          startMs: startMs,
          endMs: endMs,
          label: trailStageLabel(TrailPhase.junto, speed),
          first: 0,
          last: path.measureCount - 1,
        ),
    ];
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

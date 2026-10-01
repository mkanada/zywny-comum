// J03 — Etapas da trilha: o vocabulário de fases e a unidade guardada.
library;

import '../practice/hand.dart';
import '../practice/practice_controller.dart' show PracticeMode;

/// Compassos por trecho padrão e mínimo (J00). Os degraus 50/75/100 e os 90%
/// também são constantes do código, não configuração.
const int kTrailDefaultMeasures = 5;
const int kTrailMinMeasures = 3;

/// Degraus de andamento das fases com tempo (fração do original).
const List<double> kTrailSpeeds = [0.5, 0.75, 1.0];

/// Tipo de exercício de uma etapa (J00, "Etapas de um trecho").
enum TrailPhase {
  notasD(PracticeMode.wait, Hand.direita, 'Notas da direita'),
  notasE(PracticeMode.wait, Hand.esquerda, 'Notas da esquerda'),
  notasJ(PracticeMode.wait, Hand.ambas, 'Notas juntas'),
  ritmoD(PracticeMode.rhythm, Hand.direita, 'Ritmo da direita'),
  ritmoE(PracticeMode.rhythm, Hand.esquerda, 'Ritmo da esquerda'),
  junto(PracticeMode.realtime, Hand.ambas, 'Tudo junto no ritmo');

  const TrailPhase(this.mode, this.hand, this.label);

  final PracticeMode mode;
  final Hand hand;
  final String label;
}

/// Uma etapa: um trecho × uma fase × (um degrau, se houver). É a unidade que
/// se aprova, pula e guarda. O `id` é estável para o corte (`n`): mudar o N
/// invalida o progresso (o plano tem outro corte e outros ids).
class TrailStage {
  const TrailStage({
    required this.id,
    required this.segment,
    required this.phase,
    required this.speed,
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.first,
    required this.last,
    this.isReinforcement = false,
  });

  /// `t<trecho>.<fase>[.<degrau>]` (`t0.notasD`, `t0.ritmoE.75`,
  /// `t0.junto.100`) ou `final.50/75/100` na fase final.
  final String id;

  /// Índice do trecho em `cutSegments`, ou `null` na fase final.
  final int? segment;
  final TrailPhase phase;

  /// Fração do andamento original, ou `null` no modo espera (livre).
  final double? speed;
  final double startMs;
  final double endMs;

  /// O que a faixa e a gaveta mostram ("Ritmo da esquerda 75%").
  final String label;

  /// Compassos lógicos do trecho (índices em `TrailPath.logical`); na fase
  /// final, o caminho inteiro (0..medida-1). A gaveta mostra "compassos
  /// 5–9" a partir daqui.
  final int first;
  final int last;

  /// Bloco de reforço (J07): etapa transitória fora do plano, não guardada.
  final bool isReinforcement;
}

/// Rótulo de etapa: a fase mais o degrau em porcentagem, quando houver.
String trailStageLabel(TrailPhase phase, double? speed) => speed == null
    ? phase.label
    : '${phase.label} ${(speed * 100).round()}%';

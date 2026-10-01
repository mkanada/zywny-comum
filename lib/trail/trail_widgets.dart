// J05 — Faixa da trilha e resumo da etapa (só apresentação; o estado mora
// em `TrailController`, e quem tem player/MIDI/motor é `lib/main.dart`).
//
// A faixa é fina e de altura fixa: sobre a partitura ela não muda a caixa
// (que dispararia re-render) — ver o comentário sobre `_onBoxSize` em
// `lib/main.dart`.
library;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'stage_result.dart' show StageResult, kTrailPassAccuracy;
import 'trail_plan.dart';
import 'trail_progress.dart' show StageState, TrailProgress;

/// "Trecho 2/6 · Notas juntas" (fase final: "Fase final · …").
String trailStripText(TrailPlan plan, TrailStageOfStrip stage) =>
    trailStripTextFor(plan.segmentCount, stage.segment, stage.label);

/// Núcleo testável do texto da faixa (sem depender de `TrailStage`).
String trailStripTextFor(int segmentCount, int? segment, String label) =>
    segment == null
    ? 'Fase final · $label'
    : 'Trecho ${segment + 1}/$segmentCount · $label';

/// Estado da etapa na faixa: melhor % da aprovada, "pulada", nada se
/// pendente.
String trailStateText(TrailProgress progress, String stageId) {
  final record = progress.records[stageId];
  return switch (record?.state) {
    StageState.aprovada => '${record!.best}%',
    StageState.pulada => 'pulada',
    _ => '',
  };
}

/// Só o que a faixa precisa de uma etapa (para testes sem plano real).
class TrailStageOfStrip {
  const TrailStageOfStrip({required this.segment, required this.label});

  final int? segment;
  final String label;
}

/// Faixa fina da trilha ("Trecho 2/6 · Notas juntas", começar/parar).
class TrailStrip extends StatelessWidget {
  const TrailStrip({
    super.key,
    required this.text,
    required this.stateText,
    required this.running,
    required this.onStart,
    required this.onStop,
    this.onTap,
  });

  final String text;
  final String stateText;
  final bool running;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kTrailStripHeight,
      padding: const EdgeInsets.only(left: 4, right: 12),
      decoration: const BoxDecoration(
        color: kPanelSideBg,
        border: Border(bottom: BorderSide(color: kBorderPanel)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: running ? 'Parar etapa' : 'Começar etapa',
            onPressed: running ? onStop : onStart,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            color: kAccentDark,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (stateText.isNotEmpty)
                      TextSpan(
                        text: ' · $stateText',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kInkCaption,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Altura fixa da faixa (não muda a caixa da partitura).
const double kTrailStripHeight = 34;

/// O que o resumo devolve: o botão que o aluno tocou.
enum StageSummaryAction { next, retry, skip }

/// Resumo da etapa (folha nova, não o `showPracticeSummary`): porcentagem
/// grande, aprovado/faltou, compassos com erro (números lógicos) e os botões
/// do J00. "Pular" pede confirmação curta. Fechar sem escolher devolve
/// `null` (nada acontece).
Future<StageSummaryAction?> showStageSummary(
  BuildContext context, {
  required String stageRef,
  required StageResult result,
  required List<int> badLogical,
  required bool isLast,
}) {
  final passed = result.passed;
  final missing = (kTrailPassAccuracy * 100).round() - result.percent;
  return showModalBottomSheet<StageSummaryAction>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(stageRef, style: const TextStyle(color: kInkCaption)),
            const SizedBox(height: 4),
            Text(
              '${result.percent}%',
              style: serifDisplay(fontSize: 40),
            ),
            Text(
              passed ? 'Aprovado' : 'Faltou $missing%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: passed ? kGoodColor : kBadColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badLogical.isEmpty
                  ? 'Sem compassos com erro apontados'
                  : 'Compassos com erro: ${badLogical.join(', ')}',
            ),
            const SizedBox(height: 12),
            if (passed) ...[
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, StageSummaryAction.next),
                child: Text(isLast ? 'Concluir' : 'Próxima etapa'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, StageSummaryAction.retry),
                child: const Text('Repetir'),
              ),
            ] else ...[
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, StageSummaryAction.retry),
                child: const Text('Tentar de novo'),
              ),
              TextButton(
                onPressed: () async {
                  final skip = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Pular etapa?'),
                      content: const Text(
                        'A etapa fica marcada como pulada.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Continuar aqui'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Pular'),
                        ),
                      ],
                    ),
                  );
                  if (skip == true && context.mounted) {
                    Navigator.pop(context, StageSummaryAction.skip);
                  }
                },
                child: const Text('Pular etapa'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

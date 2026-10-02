// J05 — Faixa da trilha e resumo da etapa (só apresentação; o estado mora
// em `TrailController`, e quem tem player/MIDI/motor é `lib/main.dart`).
//
// A faixa é fina e de altura fixa: sobre a partitura ela não muda a caixa
// (que dispararia re-render) — ver o comentário sobre `_onBoxSize` em
// `lib/main.dart`.
library;

import 'package:flutter/material.dart';

import '../ui/phone_chrome.dart' show kPhoneTitleBarHeight;
import '../ui/theme.dart';
import 'stage_result.dart' show StageResult, kTrailPassAccuracy;
import 'trail_controller.dart' show ReinforcementView;
import 'trail_plan.dart';
import 'trail_progress.dart' show StageState, TrailProgress, TrailResume;
import 'trail_stage.dart' show kTrailMinMeasures;

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

/// A informação da trilha na barra do título do celular (U01): etapa, estado
/// e um "▾" que avisa que toca para abrir a gaveta. Sem [onTap] (trilha
/// indisponível) é só texto. Não ocupa área da partitura.
class TrailTitleChip extends StatelessWidget {
  const TrailTitleChip({
    super.key,
    required this.text,
    this.stateText = '',
    this.onTap,
  });

  final String text;
  final String stateText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: kPhoneTitleBarHeight,
        alignment: Alignment.centerLeft,
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
                  style: const TextStyle(fontSize: 12, color: kInkCaption),
                ),
              if (onTap != null)
                const TextSpan(
                  text: ' ▾',
                  style: TextStyle(fontSize: 12, color: kInkCaption),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Altura fixa da faixa (não muda a caixa da partitura).
const double kTrailStripHeight = 34;

/// O que o resumo devolve: o botão que o aluno tocou.
enum StageSummaryAction { next, retry, skip, backToCurrent, train }

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

  // Etapa refeita fora da atual (J06): oferece voltar a ela.
  bool showBackToCurrent = false,

  // Fase final reprovada com reforço (J07): o botão principal treina os
  // blocos em vez de tentar de novo.
  int? blockCount,
}) {
  final passed = result.passed;
  final goal = (kTrailPassAccuracy * 100).round();
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
            Text('${result.percent}%', style: serifDisplay(fontSize: 40)),
            Text(
              passed
                  ? 'Aprovado · meta $goal%'
                  : 'Precisa de $goal% para passar',
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
            if (showBackToCurrent)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, StageSummaryAction.backToCurrent),
                child: const Text('Voltar à etapa atual'),
              ),
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
              if (blockCount != null)
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, StageSummaryAction.train),
                  child: Text('Treinar os trechos com erro ($blockCount)'),
                )
              else
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
                      content: const Text('A etapa fica marcada como pulada.'),
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

/// O que a conclusão devolve: para onde o aluno vai.
enum TrailConclusionAction { library, free }

/// Tela de conclusão (J07): a `final.100` aprovada conclui a trilha.
Future<TrailConclusionAction?> showTrailConclusion(BuildContext context) {
  return showModalBottomSheet<TrailConclusionAction>(
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
            Text('Trilha concluída!', style: serifDisplay(fontSize: 28)),
            const SizedBox(height: 4),
            const Text('A música inteira a 100% foi aprovada.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, TrailConclusionAction.library),
              child: const Text('Voltar à biblioteca'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, TrailConclusionAction.free),
              child: const Text('Continuar em treino livre'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Confirmação curta antes de zerar a trilha (troca de N, reinício).
Future<bool> confirmTrailReset(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Gaveta da trilha (J06): todos os trechos e etapas agrupados, com estado
/// de cada uma. Abre com um toque na faixa; em paisagem é uma coluna lateral
/// rolável como a gaveta de opções.
class TrailDrawer extends StatelessWidget {
  const TrailDrawer({
    super.key,
    required this.plan,
    required this.progress,
    required this.selectedId,
    required this.currentId,
    required this.onClose,
    required this.onSelectStage,
    required this.onSkipCurrent,
    required this.onRestartTrail,
    this.blocks = const [],
  });

  final TrailPlan plan;
  final TrailProgress progress;

  /// Etapa que a faixa mostra (`null` com a trilha concluída).
  final String? selectedId;

  /// Primeira pendente (`null` com a trilha concluída).
  final String? currentId;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectStage;
  final VoidCallback onSkipCurrent;
  final VoidCallback onRestartTrail;

  /// Blocos de reforço à vista (J07): o grupo "Fase final" os lista
  /// enquanto existirem (só leitura — roda-se pela faixa).
  final List<ReinforcementView> blocks;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: const ColoredBox(color: kScrim),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 400,
          child: Material(
            color: kSurface,
            elevation: 8,
            child: SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Trilha de estudo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kInk,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          iconSize: 20,
                          color: kIconQuiet,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (currentId != null)
                      OutlinedButton.icon(
                        onPressed: onSkipCurrent,
                        icon: const Icon(Icons.skip_next, size: 18),
                        label: const Text('Pular etapa atual'),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (var seg = 0; seg < plan.segmentCount; seg++)
                            _segmentGroup(seg),
                          _finalGroup(),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await confirmTrailReset(
                          context,
                          title: 'Reiniciar trilha?',
                          message: 'O progresso deste hino volta a zero. Só este hino.',
                          confirmLabel: 'Reiniciar',
                        );
                        if (ok) onRestartTrail();
                      },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reiniciar trilha'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _segmentGroup(int seg) {
    final stages = [
      for (final s in plan.stages)
        if (s.segment == seg) s,
    ];
    if (stages.isEmpty) return const SizedBox.shrink();
    final first = stages.first;
    final done = stages
        .where((s) => progress.stateOf(s.id) != StageState.pendente)
        .length;
    return ExpansionTile(
      initiallyExpanded: stages.any((s) => s.id == currentId),
      title: Text(
        'Trecho ${seg + 1} · compassos ${first.first + 1}–${first.last + 1} '
        '· $done/${stages.length}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      children: [for (final s in stages) _stageRow(s.id, s.label)],
    );
  }

  Widget _stageRow(String id, String label) {
    final open = progress.isOpen(plan, id);
    final record = progress.records[id];
    final state = record?.state ?? StageState.pendente;
    final IconData icon;
    final Color? iconColor;
    var trailing = '';
    if (!open) {
      icon = Icons.lock;
      iconColor = kInkCaption;
    } else if (state == StageState.aprovada) {
      icon = Icons.check_circle;
      iconColor = kGoodColor;
      trailing = '${record!.best}%';
    } else if (state == StageState.pulada) {
      icon = Icons.skip_next;
      iconColor = kInkCaption;
      trailing = 'pulada';
    } else if (id == currentId) {
      icon = Icons.play_arrow;
      iconColor = kAccentDark;
      trailing = 'atual';
    } else {
      icon = Icons.circle_outlined;
      iconColor = kInkCaption;
    }
    return ListTile(
      dense: true,
      enabled: open,
      leading: Icon(icon, size: 20, color: iconColor),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: trailing.isEmpty
          ? null
          : Text(trailing, style: const TextStyle(fontSize: 12)),
      onTap: open ? () => onSelectStage(id) : null,
    );
  }

  Widget _finalGroup() {
    final finals = [
      for (final s in plan.stages)
        if (s.segment == null) s,
    ];
    if (finals.isEmpty && blocks.isEmpty) {
      // J07 faz a fase final funcionar; até lá, só o grupo à vista.
      return const ListTile(
        dense: true,
        enabled: false,
        title: Text('Fase final', style: TextStyle(fontSize: 14)),
        trailing: Text('em breve', style: TextStyle(fontSize: 12)),
      );
    }
    final done = finals
        .where((s) => progress.stateOf(s.id) != StageState.pendente)
        .length;
    return ExpansionTile(
      initiallyExpanded:
          finals.any((s) => s.id == currentId) || blocks.isNotEmpty,
      title: Text(
        finals.isEmpty ? 'Fase final' : 'Fase final · $done/${finals.length}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      children: [
        for (final s in finals) _stageRow(s.id, s.label),
        for (var i = 0; i < blocks.length; i++) _blockRow(i),
      ],
    );
  }

  Widget _blockRow(int index) {
    final block = blocks[index];
    final String trailing;
    final IconData icon;
    if (block.state == StageState.aprovada) {
      trailing = 'aprovada';
      icon = Icons.check_circle;
    } else if (block.state == StageState.pulada) {
      trailing = 'pulada';
      icon = Icons.skip_next;
    } else if (block.isCurrent) {
      trailing = 'atual';
      icon = Icons.play_arrow;
    } else {
      trailing = '';
      icon = Icons.circle_outlined;
    }
    return ListTile(
      dense: true,
      enabled: false,
      leading: Icon(icon, size: 20, color: kInkCaption),
      title: Text(
        'Reforço ${index + 1} · compassos ${block.first + 1}–${block.last + 1}',
        style: const TextStyle(fontSize: 14),
      ),
      trailing: trailing.isEmpty
          ? null
          : Text(trailing, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Seletor de compassos por trecho (J06): `- N +`, de 3 ao máximo.
class TrailNSelector extends StatelessWidget {
  const TrailNSelector({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Compassos por trecho',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        IconButton(
          tooltip: 'Menos compassos por trecho',
          onPressed: value > kTrailMinMeasures
              ? () => onChanged(value - 1)
              : null,
          iconSize: 20,
          color: kIconQuiet,
          icon: const Icon(Icons.remove),
        ),
        Text(
          '$value',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'Mais compassos por trecho',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          iconSize: 20,
          color: kIconQuiet,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Onde o hino parou, para o cartão "Continuar" (J09).
String trailResumeText(TrailResume resume) => resume.segment == null
    ? 'Fase final · ${resume.label}'
    : 'Trecho ${resume.segment! + 1}/${resume.segments} · ${resume.label}';

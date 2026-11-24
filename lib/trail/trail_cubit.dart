// J05 — Estado da trilha na tela: plano + progresso + etapa selecionada.
//
// O Cubit da trilha vai num controlador próprio (não no estado da tela):
// `lib/main.dart` só cola callbacks. A etapa selecionada é a atual por padrão;
// refazer/pular/gaveta vêm no J06.
//
// BL10: era um `ChangeNotifier`. Os métodos seguem síncronos e quem decide
// lê `state` na hora; o `emit` põe o estado novo e só depois se grava o
// progresso (`recordDone` e `skipSelected` gravam depois do `emit`).
library;

import 'package:zywny_bloc/zywny_bloc.dart';

import 'reinforcement.dart';
import 'stage_result.dart';
import 'trail_path.dart';
import 'trail_plan.dart';
import 'trail_progress.dart';
import 'trail_progress_cubit.dart';
import 'trail_stage.dart';

/// Um bloco de reforço à vista (J07): intervalo lógico + estado transitório.
class ReinforcementView {
  const ReinforcementView({
    required this.first,
    required this.last,
    required this.state,
    required this.isCurrent,
  });

  final int first;
  final int last;
  final StageState state;
  final bool isCurrent;
}

/// O que a trilha guarda: o progresso, a etapa escolhida, o resultado da última
/// passagem, o modo livre, se há etapa rodando e os blocos de reforço (J07).
/// Imutável: cada mudança é um `copyWith` que vai pelo `emit`.
class TrailState extends Equatable {
  const TrailState({
    required this.progress,
    this.selectedId,
    this.pinnedBlock,
    this.lastResult,
    this.lastStage,
    this.freeMode = false,
    this.running = false,
    this.blocks = const [],
    this.blockStates = const {},
    this.blockSpeed,
  });

  final TrailProgress progress;

  /// Id da etapa que o aluno escolheu (`null`: a atual).
  final String? selectedId;

  /// Bloco de reforço que o "repetir" do resumo prendeu na seleção: ao ser
  /// aprovado, o bloco corrente já passou para o seguinte.
  final TrailStage? pinnedBlock;

  /// Resultado da última passagem e a etapa que a fez, para o resumo (J05).
  final StageResult? lastResult;
  final TrailStage? lastStage;

  /// Treino livre (controles de hoje) em vez da trilha.
  final bool freeMode;

  /// Uma etapa está em curso (entre começar e terminar/parar).
  final bool running;

  /// Blocos de reforço (intervalos lógicos) e o estado de cada um; a ausência
  /// no mapa é pendente.
  final List<({int first, int last})> blocks;
  final Map<int, StageState> blockStates;

  /// Degrau reprovado em que os blocos rodam.
  final double? blockSpeed;

  /// Os campos que podem ficar `null` vêm como função (`() => null` limpa).
  TrailState copyWith({
    TrailProgress? progress,
    String? Function()? selectedId,
    TrailStage? Function()? pinnedBlock,
    StageResult? Function()? lastResult,
    TrailStage? Function()? lastStage,
    bool? freeMode,
    bool? running,
    List<({int first, int last})>? blocks,
    Map<int, StageState>? blockStates,
    double? Function()? blockSpeed,
  }) => TrailState(
    progress: progress ?? this.progress,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    pinnedBlock: pinnedBlock == null ? this.pinnedBlock : pinnedBlock(),
    lastResult: lastResult == null ? this.lastResult : lastResult(),
    lastStage: lastStage == null ? this.lastStage : lastStage(),
    freeMode: freeMode ?? this.freeMode,
    running: running ?? this.running,
    blocks: blocks ?? this.blocks,
    blockStates: blockStates ?? this.blockStates,
    blockSpeed: blockSpeed == null ? this.blockSpeed : blockSpeed(),
  );

  @override
  List<Object?> get props => [
    progress,
    selectedId,
    pinnedBlock,
    lastResult,
    lastStage,
    freeMode,
    running,
    blocks,
    blockStates,
    blockSpeed,
  ];
}

/// Índice do primeiro bloco de reforço pendente de [state], ou `null`.
int? _pendingBlock(TrailState state) {
  for (var i = 0; i < state.blocks.length; i++) {
    if ((state.blockStates[i] ?? StageState.pendente) == StageState.pendente) {
      return i;
    }
  }
  return null;
}

/// Com todos os blocos feitos (ou pulados), o reforço sai do estado.
TrailState _withoutFinishedBlocks(TrailState state) {
  if (_pendingBlock(state) != null) return state;
  return state.copyWith(
    blocks: const [],
    blockStates: const {},
    blockSpeed: () => null,
  );
}

/// A trilha de um hino: o plano ([path], [plan]), o progresso (no estado), a
/// etapa escolhida e o treino em curso. [store] grava o progresso;
/// [pieceId] é o id de progresso dele (`null` fora da biblioteca: a trilha vale
/// na sessão, mas não grava, J03).
class TrailCubit extends Cubit<TrailState> {
  TrailCubit({
    required this.path,
    required this.plan,
    required TrailProgress progress,
    required this.store,
    required this.pieceId,
  }) : super(
         TrailState(
           progress: progress.n == plan.n
               ? progress
               : TrailProgress(n: plan.n, total: plan.stages.length),
         ),
       );

  final TrailPath path;
  final TrailPlan plan;
  final TrailProgressCubit store;

  /// O id do progresso desta trilha na biblioteca (`progressIdFor`: o da
  /// música, com o sufixo do tom se transposta); `null` fora dela (partitura
  /// avulsa): a trilha vale na sessão, mas não persiste (J03).
  final String? pieceId;

  TrailProgress get progress => state.progress;

  /// A etapa que a faixa mostra e o começar arma (a atual por padrão; o
  /// bloco de reforço corrente enquanto houver reforço).
  TrailStage? get selected {
    final pinned = state.pinnedBlock;
    if (pinned != null) return pinned;
    final id = state.selectedId;
    if (id != null) {
      for (final s in plan.stages) {
        if (s.id == id) return s;
      }
    }
    final block = currentBlockStage();
    if (block != null) return block;
    return progress.current(plan);
  }

  /// Só etapa aberta pode ser selecionada (a atual e as anteriores). Com
  /// etapa rodando a seleção não muda: quem chama encerra a etapa antes.
  void select(String id) {
    if (state.running || !progress.isOpen(plan, id)) return;
    if (state.selectedId == id && state.pinnedBlock == null) return;
    emit(state.copyWith(selectedId: () => id, pinnedBlock: () => null));
  }

  /// Volta à atual (a primeira pendente) — o "próxima etapa" do resumo.
  void next() {
    if (state.running) return;
    if (state.selectedId == null && state.pinnedBlock == null) return;
    emit(state.copyWith(selectedId: () => null, pinnedBlock: () => null));
  }

  /// "Repetir" do resumo: volta a selecionar [stage], a que acabou de rodar.
  /// Ao aprovar, a atual (a primeira pendente) já andou para a seguinte —
  /// sem isto o começar armaria a próxima etapa. Um bloco de reforço que
  /// não existe mais (o reforço acabou) não é preso: vale a atual.
  void repeat(TrailStage stage) {
    if (state.running) return;
    if (stage.isReinforcement) {
      if (blockIndexOf(stage) == null) return;
      emit(state.copyWith(pinnedBlock: () => stage));
      return;
    }
    select(stage.id);
  }

  /// Resultado da última passagem, para o resumo (J05).
  StageResult? get lastResult => state.lastResult;
  TrailStage? get lastStage => state.lastStage;

  void clearResult() =>
      emit(state.copyWith(lastResult: () => null, lastStage: () => null));

  /// Guarda o resultado da selecionada (aprova/pula por `StageResult`,
  /// melhor só sobe) e expõe para o resumo. Carimba onde parou para o
  /// "Continuar" da biblioteca (J09).
  Future<void> recordDone(StageResult result) async {
    final stage = selected;
    if (stage == null) return;
    emit(
      state.copyWith(
        progress: _stamped(progress.recordResult(stage.id, result)),
        lastResult: () => result,
        lastStage: () => stage,
      ),
    );
    final id = pieceId;
    if (id != null) await store.save(id, progress);
  }

  /// Pula a selecionada (só pendente vira pulada).
  Future<void> skipSelected() async {
    final stage = selected;
    if (stage == null) return;
    final updated = progress.skip(stage.id);
    if (identical(updated, progress)) return;
    emit(state.copyWith(progress: _stamped(updated)));
    final id = pieceId;
    if (id != null) await store.save(id, progress);
  }

  /// Onde parou (etapa atual), para o resumo guardado.
  TrailProgress _stamped(TrailProgress progress) {
    final current = progress.current(plan);
    if (current == null) {
      return TrailProgress(
        n: progress.n,
        total: progress.total,
        records: progress.records,
      );
    }
    return TrailProgress(
      n: progress.n,
      total: progress.total,
      records: progress.records,
      resume: TrailResume(
        stageId: current.id,
        label: current.label,
        segment: current.segment,
        segments: plan.segmentCount,
      ),
    );
  }

  /// Treino livre (controles de hoje) em vez da trilha. Nada do modo livre
  /// toca no progresso.
  bool get freeMode => state.freeMode;
  void setFreeMode(bool value) {
    if (state.freeMode == value) return;
    emit(state.copyWith(freeMode: value));
  }

  /// Uma etapa está em curso (entre começar e terminar/parar).
  bool get running => state.running;
  void setRunning(bool value) {
    if (state.running == value) return;
    emit(state.copyWith(running: value));
  }

  // -------------------------------------------------------------------------
  // Reforço (J07): blocos transitórios em volta dos compassos errados da
  // fase final reprovada. Não são etapas do plano e não persistem: fechar a
  // música descarta (o Cubit é refeito ao abrir).
  // -------------------------------------------------------------------------

  /// Há reforço pendente.
  bool get reinforcing => state.blocks.isNotEmpty;

  /// Degrau reprovado em que os blocos rodam.
  double? get reinforcementSpeed => state.blockSpeed;

  /// Índice do bloco corrente (primeiro pendente), ou `null` sem reforço.
  int? get reinforcementIndex => _pendingBlock(state);

  /// Etapa sintética para rodar o bloco corrente (realtime, ambas, no
  /// degrau reprovado, com contagem e metrônomo — como uma etapa comum).
  TrailStage? currentBlockStage() {
    final index = reinforcementIndex;
    final speed = state.blockSpeed;
    if (index == null || speed == null) return null;
    final block = state.blocks[index];
    final startMs = path.logical[block.first].startMs;
    final endMs = path.logical[block.last].endMs;
    final pct = (speed * 100).round();
    return TrailStage(
      id: 'reforco.$index',
      segment: null,
      phase: TrailPhase.junto,
      speed: speed,
      startMs: startMs,
      endMs: endMs,
      label:
          'Reforço ${index + 1}/${state.blocks.length} · '
          'compassos ${block.first + 1}–${block.last + 1} · $pct%',
      first: block.first,
      last: block.last,
      isReinforcement: true,
    );
  }

  /// Blocos à vista para a gaveta (grupo "Fase final").
  List<ReinforcementView> get blockViews {
    final current = reinforcementIndex;
    return [
      for (var i = 0; i < state.blocks.length; i++)
        ReinforcementView(
          first: state.blocks[i].first,
          last: state.blocks[i].last,
          state: state.blockStates[i] ?? StageState.pendente,
          isCurrent: i == current,
        ),
    ];
  }

  /// Monta o reforço da última etapa (fase final) reprovada: converte os
  /// compassos com erro (ocorrências) para lógicos e aplica as 4 regras
  /// (J02). Devolve `true` com reforço útil; `false` sem reforço (bloco
  /// único cobrindo a música inteira, ou nenhum compasso apontado) — aí
  /// vale só "tentar de novo".
  bool startReinforcement(StageResult result) {
    final failed = state.lastStage;
    final speed = failed?.speed;
    if (failed == null || failed.segment != null || speed == null) {
      return false;
    }
    final bad = <int>{
      for (final occurrence in result.badMeasures) ?path.logicalOf(occurrence),
    };
    final blocks = reinforcementBlocks(bad, path.measureCount);
    if (blocks.isEmpty) return false;
    if (blocks.length == 1 &&
        blocks.single.first == 0 &&
        blocks.single.last == path.measureCount - 1) {
      return false;
    }
    emit(
      state.copyWith(
        blocks: blocks,
        blockStates: const {},
        blockSpeed: () => speed,
      ),
    );
    return true;
  }

  /// Guarda o resultado do bloco (só aprovado marca; pulo à parte). Com
  /// todos feitos, o reforço sai e a final reabre.
  void recordBlockDone(int index, StageResult result) {
    if (index < 0 || index >= state.blocks.length) return;
    var next = state.copyWith(pinnedBlock: () => null);
    if (result.passed) {
      next = _withoutFinishedBlocks(
        next.copyWith(
          blockStates: {...next.blockStates, index: StageState.aprovada},
        ),
      );
    }
    emit(next);
  }

  /// Pula o bloco (não marca a final como pulada). Com todos feitos, a
  /// final reabre.
  void skipBlock(int index) {
    if (index < 0 || index >= state.blocks.length) return;
    final semFixa = state.copyWith(pinnedBlock: () => null);
    if ((state.blockStates[index] ?? StageState.pendente) !=
        StageState.pendente) {
      emit(semFixa);
      return;
    }
    emit(
      _withoutFinishedBlocks(
        semFixa.copyWith(
          blockStates: {...semFixa.blockStates, index: StageState.pulada},
        ),
      ),
    );
  }

  /// Índice do bloco que [stage] é (etapa de reforço), ou `null` se é etapa
  /// do plano.
  int? blockIndexOf(TrailStage stage) {
    if (!stage.isReinforcement) return null;
    for (var i = 0; i < state.blocks.length; i++) {
      if (state.blocks[i].first == stage.first &&
          state.blocks[i].last == stage.last) {
        return i;
      }
    }
    return null;
  }
}

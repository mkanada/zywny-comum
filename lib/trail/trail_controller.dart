// J05 — Estado da trilha na tela: plano + progresso + etapa selecionada.
//
// O `ChangeNotifier` da trilha vai num controlador próprio (não no estado da
// tela): `lib/main.dart` só cola callbacks. A etapa selecionada é a atual
// por padrão; refazer/pular/gaveta vêm no J06.
library;

import 'package:flutter/foundation.dart';

import 'reinforcement.dart';
import 'stage_result.dart';
import 'trail_path.dart';
import 'trail_plan.dart';
import 'trail_progress.dart';
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

class TrailController extends ChangeNotifier {
  TrailController({
    required this.path,
    required this.plan,
    required TrailProgress progress,
    required this.store,
    required this.hymnNumber,
  }) : _progress = progress.n == plan.n
           ? progress
           : TrailProgress(n: plan.n, total: plan.stages.length);

  final TrailPath path;
  final TrailPlan plan;
  final TrailProgressStore store;

  /// Número do hino na biblioteca; `null` fora dela (partitura avulsa): a
  /// trilha vale na sessão, mas não persiste (J03).
  final int? hymnNumber;

  TrailProgress _progress;
  TrailProgress get progress => _progress;

  String? _selectedId;

  /// A etapa que a faixa mostra e o começar arma (a atual por padrão; o
  /// bloco de reforço corrente enquanto houver reforço).
  TrailStage? get selected {
    final pinned = _pinnedBlock;
    if (pinned != null) return pinned;
    final id = _selectedId;
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
    if (_running || !progress.isOpen(plan, id)) return;
    if (_selectedId == id && _pinnedBlock == null) return;
    _selectedId = id;
    _pinnedBlock = null;
    notifyListeners();
  }

  /// Volta à atual (a primeira pendente) — o "próxima etapa" do resumo.
  void next() {
    if (_running) return;
    if (_selectedId == null && _pinnedBlock == null) return;
    _selectedId = null;
    _pinnedBlock = null;
    notifyListeners();
  }

  /// Bloco de reforço que o "repetir" do resumo prendeu na seleção: ao ser
  /// aprovado, o bloco corrente já passou para o seguinte.
  TrailStage? _pinnedBlock;

  /// "Repetir" do resumo: volta a selecionar [stage], a que acabou de rodar.
  /// Ao aprovar, a atual (a primeira pendente) já andou para a seguinte —
  /// sem isto o começar armaria a próxima etapa. Um bloco de reforço que
  /// não existe mais (o reforço acabou) não é preso: vale a atual.
  void repeat(TrailStage stage) {
    if (_running) return;
    if (stage.isReinforcement) {
      if (blockIndexOf(stage) == null) return;
      _pinnedBlock = stage;
      notifyListeners();
      return;
    }
    select(stage.id);
  }

  StageResult? _lastResult;
  TrailStage? _lastStage;

  /// Resultado da última passagem, para o resumo (J05).
  StageResult? get lastResult => _lastResult;
  TrailStage? get lastStage => _lastStage;

  void clearResult() {
    _lastResult = null;
    _lastStage = null;
    notifyListeners();
  }

  /// Guarda o resultado da selecionada (aprova/pula por `StageResult`,
  /// melhor só sobe) e expõe para o resumo. Carimba onde parou para o
  /// "Continuar" da biblioteca (J09).
  Future<void> recordDone(StageResult result) async {
    final stage = selected;
    if (stage == null) return;
    _progress = _stamped(_progress.recordResult(stage.id, result));
    _lastResult = result;
    _lastStage = stage;
    final number = hymnNumber;
    if (number != null) await store.save(number, _progress);
    notifyListeners();
  }

  /// Pula a selecionada (só pendente vira pulada).
  Future<void> skipSelected() async {
    final stage = selected;
    if (stage == null) return;
    final updated = _progress.skip(stage.id);
    if (identical(updated, _progress)) return;
    _progress = _stamped(updated);
    final number = hymnNumber;
    if (number != null) await store.save(number, _progress);
    notifyListeners();
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

  bool _freeMode = false;

  /// Treino livre (controles de hoje) em vez da trilha. Nada do modo livre
  /// toca no progresso.
  bool get freeMode => _freeMode;
  void setFreeMode(bool value) {
    if (_freeMode == value) return;
    _freeMode = value;
    notifyListeners();
  }

  bool _running = false;

  /// Uma etapa está em curso (entre começar e terminar/parar).
  bool get running => _running;
  void setRunning(bool value) {
    if (_running == value) return;
    _running = value;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Reforço (J07): blocos transitórios em volta dos compassos errados da
  // fase final reprovada. Não são etapas do plano e não persistem: fechar a
  // música descarta (o controlador é refeito ao abrir).
  // -------------------------------------------------------------------------

  List<({int first, int last})> _blocks = const [];
  final Map<int, StageState> _blockStates = {};
  double? _blockSpeed;

  /// Há reforço pendente.
  bool get reinforcing => _blocks.isNotEmpty;

  /// Degrau reprovado em que os blocos rodam.
  double? get reinforcementSpeed => _blockSpeed;

  /// Índice do bloco corrente (primeiro pendente), ou `null` sem reforço.
  int? get reinforcementIndex {
    for (var i = 0; i < _blocks.length; i++) {
      if ((_blockStates[i] ?? StageState.pendente) == StageState.pendente) {
        return i;
      }
    }
    return null;
  }

  /// Etapa sintética para rodar o bloco corrente (realtime, ambas, no
  /// degrau reprovado, com contagem e metrônomo — como uma etapa comum).
  TrailStage? currentBlockStage() {
    final index = reinforcementIndex;
    final speed = _blockSpeed;
    if (index == null || speed == null) return null;
    final block = _blocks[index];
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
          'Reforço ${index + 1}/${_blocks.length} · '
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
      for (var i = 0; i < _blocks.length; i++)
        ReinforcementView(
          first: _blocks[i].first,
          last: _blocks[i].last,
          state: _blockStates[i] ?? StageState.pendente,
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
    final failed = _lastStage;
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
    _blocks = blocks;
    _blockStates.clear();
    _blockSpeed = speed;
    notifyListeners();
    return true;
  }

  /// Guarda o resultado do bloco (só aprovado marca; pulo à parte). Com
  /// todos feitos, o reforço sai e a final reabre.
  void recordBlockDone(int index, StageResult result) {
    if (index < 0 || index >= _blocks.length) return;
    _pinnedBlock = null;
    if (result.passed) {
      _blockStates[index] = StageState.aprovada;
      _maybeClearReinforcement();
    }
    notifyListeners();
  }

  /// Pula o bloco (não marca a final como pulada). Com todos feitos, a
  /// final reabre.
  void skipBlock(int index) {
    if (index < 0 || index >= _blocks.length) return;
    _pinnedBlock = null;
    if ((_blockStates[index] ?? StageState.pendente) != StageState.pendente) {
      return;
    }
    _blockStates[index] = StageState.pulada;
    _maybeClearReinforcement();
    notifyListeners();
  }

  void _maybeClearReinforcement() {
    if (reinforcementIndex == null) {
      _blocks = const [];
      _blockStates.clear();
      _blockSpeed = null;
    }
  }

  /// Índice do bloco que [stage] é (etapa de reforço), ou `null` se é etapa
  /// do plano.
  int? blockIndexOf(TrailStage stage) {
    if (!stage.isReinforcement) return null;
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].first == stage.first && _blocks[i].last == stage.last) {
        return i;
      }
    }
    return null;
  }
}

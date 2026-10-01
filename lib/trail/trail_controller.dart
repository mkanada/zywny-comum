// J05 — Estado da trilha na tela: plano + progresso + etapa selecionada.
//
// O `ChangeNotifier` da trilha vai num controlador próprio (não no estado da
// tela): `lib/main.dart` só cola callbacks. A etapa selecionada é a atual
// por padrão; refazer/pular/gaveta vêm no J06.
library;

import 'package:flutter/foundation.dart';

import 'stage_result.dart';
import 'trail_path.dart';
import 'trail_plan.dart';
import 'trail_progress.dart';
import 'trail_stage.dart';

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

  /// A etapa que a faixa mostra e o começar arma (a atual por padrão).
  TrailStage? get selected {
    final id = _selectedId;
    if (id != null) {
      for (final s in plan.stages) {
        if (s.id == id) return s;
      }
    }
    return progress.current(plan);
  }

  /// Só etapa aberta pode ser selecionada (a atual e as anteriores).
  void select(String id) {
    if (!progress.isOpen(plan, id)) return;
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Volta à atual (a primeira pendente) — o "próxima etapa" do resumo.
  void next() {
    if (_selectedId == null) return;
    _selectedId = null;
    notifyListeners();
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
  /// melhor só sobe) e expõe para o resumo.
  Future<void> recordDone(StageResult result) async {
    final stage = selected;
    if (stage == null) return;
    _progress = _progress.recordResult(stage.id, result);
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
    _progress = updated;
    final number = hymnNumber;
    if (number != null) await store.save(number, _progress);
    notifyListeners();
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
}

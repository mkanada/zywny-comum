// J03 — Progresso da trilha: o que o aluno já fez, guardado por hino.
//
// Desbloqueio linear (J00): as etapas têm uma ordem (trecho 0 inteiro,
// trecho 1…, fase final). A atual é a primeira pendente; estão abertas a
// atual e todas as anteriores. Refazer nunca tira a aprovação; pulada que
// depois passa vira aprovada.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stage_result.dart';
import 'trail_plan.dart';
import 'trail_stage.dart';

/// Estado de uma etapa: nunca aprovada nem pulada, aprovada, ou pulada.
enum StageState { pendente, aprovada, pulada }

@immutable
class StageRecord {
  const StageRecord({required this.state, required this.best});

  final StageState state;

  /// Melhor porcentagem de qualquer tentativa (0–100).
  final int best;

  Map<String, Object?> toJson() => {'s': state.name, 'b': best};

  factory StageRecord.fromJson(Map<String, dynamic> json) {
    var state = StageState.pendente;
    for (final s in StageState.values) {
      if (s.name == json['s']) state = s;
    }
    final best = json['b'];
    return StageRecord(
      state: state,
      best: best is num ? best.round().clamp(0, 100) : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StageRecord && other.state == state && other.best == best;

  @override
  int get hashCode => Object.hash(state, best);
}

/// O que o aluno fez na trilha de um hino, no corte `n` com `total` etapas.
/// Imutável: `recordResult`/`skip` devolvem um novo valor.
@immutable
class TrailProgress {
  const TrailProgress({
    required this.n,
    required this.total,
    this.records = const {},
  });

  /// O N com que o corte foi feito. Com um plano de outro N, tudo conta
  /// como pendente (o progresso é de outro corte — J06 confirma antes de
  /// trocar e zera).
  final int n;

  /// Etapas do plano (cache para a biblioteca mostrar feito/total sem
  /// montar o plano de 600 hinos — J09).
  final int total;
  final Map<String, StageRecord> records;

  /// Trilha vazia (nada feito, sem corte conhecido).
  static const empty = TrailProgress(n: 0, total: 0);

  StageState stateOf(String id) =>
      records[id]?.state ?? StageState.pendente;

  bool _matches(TrailPlan plan) => plan.n == n;

  /// A primeira pendente do plano, ou `null` com a trilha concluída.
  /// Plano vazio ou de outro corte: a primeira do plano (nada feito nele).
  TrailStage? current(TrailPlan plan) {
    if (plan.stages.isEmpty) return null;
    if (!_matches(plan)) return plan.stages.first;
    for (final s in plan.stages) {
      if (stateOf(s.id) == StageState.pendente) return s;
    }
    return null;
  }

  /// Abertas: a atual e todas as anteriores (concluída: todas).
  bool isOpen(TrailPlan plan, String id) {
    final order = <String>[for (final s in plan.stages) s.id];
    if (!_matches(plan)) {
      return id == (order.isEmpty ? null : order.first);
    }
    final current = this.current(plan);
    if (current == null) return order.contains(id);
    return order.indexOf(id) <= order.indexOf(current.id);
  }

  /// Feitas (aprovadas + puladas — é o que destrava) no plano.
  int doneCount(TrailPlan plan) {
    if (!_matches(plan)) return 0;
    var done = 0;
    for (final s in plan.stages) {
      if (stateOf(s.id) != StageState.pendente) done++;
    }
    return done;
  }

  bool isComplete(TrailPlan plan) {
    if (plan.stages.isEmpty) return false;
    return current(plan) == null;
  }

  /// A `final.100` aprovada: a música foi concluída (a biblioteca marca).
  bool get finalApproved =>
      records['final.100']?.state == StageState.aprovada;

  /// Feitas sem plano (cache do JSON para a biblioteca — J09).
  int get done =>
      records.values.where((r) => r.state != StageState.pendente).length;

  /// Aprova se `passed`; sempre atualiza `best`; nunca rebaixa `aprovada`.
  /// Pulada que depois passa vira `aprovada`.
  TrailProgress recordResult(String id, StageResult result) {
    final current = records[id];
    final best = current == null || result.percent > current.best
        ? result.percent
        : current.best;
    final state = result.passed
        ? StageState.aprovada
        : (current?.state ?? StageState.pendente);
    return TrailProgress(
      n: n,
      total: total,
      records: {...records, id: StageRecord(state: state, best: best)},
    );
  }

  /// Só `pendente` vira `pulada`.
  TrailProgress skip(String id) {
    final current = records[id];
    if ((current?.state ?? StageState.pendente) != StageState.pendente) {
      return this;
    }
    return TrailProgress(
      n: n,
      total: total,
      records: {
        ...records,
        id: StageRecord(state: StageState.pulada, best: current?.best ?? 0),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'n': n,
    'total': total,
    'done': done,
    'records': {
      for (final e in records.entries) e.key: e.value.toJson(),
    },
  };

  factory TrailProgress.fromJson(Map<String, dynamic> json) {
    final records = <String, StageRecord>{};
    final stored = json['records'];
    if (stored is Map) {
      stored.forEach((key, value) {
        if (key is String && value is Map) {
          records[key] = StageRecord.fromJson(
            value.cast<String, dynamic>(),
          );
        }
      });
    }
    final n = json['n'];
    final total = json['total'];
    return TrailProgress(
      n: n is num ? n.round() : 0,
      total: total is num ? total.round() : 0,
      records: records,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrailProgress &&
      other.n == n &&
      other.total == total &&
      mapEquals(other.records, records);

  @override
  int get hashCode => Object.hash(n, total, records);
}

/// Guarda uma trilha por hino (`trail_<número>`, com `'v': 1`), com
/// `done`/`total` junto para a biblioteca (J09). Avisa quem escuta a cada
/// mudança — a biblioteca refaz a linha do hino ao voltar da partitura.
class TrailProgressStore extends ChangeNotifier {
  TrailProgressStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  final Map<int, TrailProgress> _byNumber = {};

  static String key(int number) => 'trail_$number';

  /// Hinos da biblioteca embutida (1–600): a leitura em lote dos resumos.
  static const int kMaxHymnNumber = 600;

  TrailProgress operator [](int number) =>
      _byNumber[number] ?? TrailProgress.empty;

  /// Resumo pronto para a biblioteca (J09): sem montar nenhum plano.
  ({int done, int total, bool completed}) summary(int number) {
    final p = _byNumber[number] ?? TrailProgress.empty;
    return (done: p.done, total: p.total, completed: p.finalApproved);
  }

  Future<void> load() async {
    _byNumber.clear();
    for (var number = 1; number <= kMaxHymnNumber; number++) {
      try {
        final text = await _prefs.getString(key(number));
        if (text == null) continue;
        _byNumber[number] = TrailProgress.fromJson(
          jsonDecode(text) as Map<String, dynamic>,
        );
      } on Object {
        // JSON estragado: trilha vazia, sem exceção (padrão do hymn_progress).
        continue;
      }
    }
    notifyListeners();
  }

  Future<void> save(int number, TrailProgress progress) {
    _byNumber[number] = progress;
    notifyListeners();
    return _prefs.setString(key(number), jsonEncode(progress.toJson()));
  }

  Future<void> reset(int number) {
    _byNumber.remove(number);
    notifyListeners();
    return _prefs.remove(key(number));
  }
}

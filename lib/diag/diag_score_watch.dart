import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_diag/diag_log.dart';

/// Põe no log a página da partitura que o [ScoreViewController] mostra
/// (cada virada) e a registra no estado do relatório de bug (`partitura`).
/// Quem cria o controller cria o observador e o descarta junto.
class DiagScoreWatch {
  DiagScoreWatch(this.controller, {required this.label, this.pageCount}) {
    controller.addListener(_onChange);
    _offState = DiagLog.setState('partitura', _snapshot);
  }

  final ScoreViewController controller;

  /// De que partitura é ("hino 001", "exercício 34d").
  final String label;

  /// Quantas páginas há (quando quem cria sabe).
  final int? pageCount;

  late final VoidCallback _offState;
  int? _lastPage;

  int? get _page => controller.isAttached ? controller.currentPage : null;

  Map<String, Object?> _snapshot() => {
    'partitura': label,
    'pagina': _page,
    'paginas': pageCount,
  };

  void _onChange() {
    final page = _page;
    if (page == null || page == _lastPage) return;
    _lastPage = page;
    DiagLog.log('pagina', '$label: página ${page + 1}/${pageCount ?? '?'}');
  }

  void dispose() {
    controller.removeListener(_onChange);
    _offState();
  }
}

// LP24.2 — A volta na hora: a conta do compasso com erro (Dart puro).
//
// O `PracticeController` anota aqui cada erro (nota errada ou perdida) pelo
// compasso dele e pergunta, quando o compasso acaba, se ele precisa voltar.
// A volta zera a tentativa do compasso e de tudo o que vem depois (o que o
// aluno tocou na folga depois da barra vai ser tocado de novo).
library;

/// Erros da tentativa em curso e voltas dadas, por compasso (a ocorrência,
/// índice de `ScoreTimeline.measures`).
class MeasureRewinds {
  final Map<int, int> _errors = {};
  final Map<int, int> _counts = {};

  /// Um erro (nota errada ou perdida) no compasso [measure].
  void error(int measure) => _errors[measure] = (_errors[measure] ?? 0) + 1;

  /// A tentativa em curso do compasso [measure] teve algum erro.
  bool hasError(int measure) => (_errors[measure] ?? 0) > 0;

  /// O compasso [measure] volta: a tentativa nova começa limpa nele e em
  /// tudo o que vem depois. Devolve o número da tentativa que começa (2 na
  /// primeira volta).
  int rewind(int measure) {
    _errors.removeWhere((m, _) => m >= measure);
    final count = (_counts[measure] ?? 0) + 1;
    _counts[measure] = count;
    return count + 1;
  }

  /// Quantas vezes cada compasso voltou (só os que voltaram).
  Map<int, int> get counts => Map.unmodifiable(_counts);
}

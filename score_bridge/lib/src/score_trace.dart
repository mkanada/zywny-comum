// Rastro da partitura (o log do relatório de bug): o `score_bridge` não
// conhece o `zywny_diag`, então quem monta o app liga [ScoreTrace.sink] ao
// log (ver `DiagScoreWatch`). Sem sink, nada é calculado nem gravado.
library;

/// Para onde vão as linhas de rastro do player e da vista; `null` desliga.
class ScoreTrace {
  const ScoreTrace._();

  /// Recebe a etiqueta (`player`, `vista`, `haste`) e o texto.
  static void Function(String tag, String message)? sink;

  static bool get enabled => sink != null;

  /// Grava [message] (só é montada se há sink: passe a função).
  static void log(String tag, String Function() message) {
    final s = sink;
    if (s == null) return;
    try {
      s(tag, message());
    } catch (_) {
      // Rastro nunca derruba a partitura.
    }
  }
}

/// Um milissegundo com uma casa, para as linhas de rastro.
String traceMs(double ms) => ms.toStringAsFixed(1);

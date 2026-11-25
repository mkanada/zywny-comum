/// As regras de tempo que os dois relógios seguem. Ficam num lugar só para que
/// [SystemClock] e [ManualClock] não divirjam.
library;

/// O atraso de um `timer` de uma vez: um atraso negativo vale zero (como no
/// `Timer` do Dart).
Duration tempoDoTimer(Duration after) =>
    after.isNegative ? Duration.zero : after;

/// Confere o intervalo de um periódico: tem de ser positivo, senão o relógio
/// dispararia sem parar.
void verificarPeriodo(Duration every) {
  if (every <= Duration.zero) {
    throw ArgumentError.value(
      every,
      'every',
      'o intervalo de um periódico tem de ser positivo',
    );
  }
}

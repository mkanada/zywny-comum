// AC05a do AC00 ("Tocar pela cifra"): a exigência de um ataque de cifra no modo
// espera. Dart puro, sem Flutter e sem o app: o app implementa esta interface
// (`ChordExpectation`, em `lib/chord_play/chord_judge.dart`), e a
// `WaitModeSession` a trata como um passo a mais, ao lado das notas da partitura
// (que seguem pelos ids).
//
// O compasso do ataque não vem daqui: sai de `onMs`, pelo `measureIndexAt` da
// rodada, como o da melodia. A numeração da grade do acorde (`ChordSpan.measure`)
// é a do documento original, e a escada só lê o tempo.
library;

/// Uma exigência de acorde num instante da partitura.
abstract interface class ChordDemand {
  /// O ataque, em ms musicais. É o `onMs` do passo a que a exigência pertence
  /// (o da melodia do mesmo instante, se há, ou o dela).
  double get onMs;

  /// A tecla é do acorde? No modo espera, a tecla que não é fica errada na hora
  /// e segura o passo enquanto estiver apertada.
  bool allows(int pitch);

  /// As teclas apertadas no ataque cumprem o acorde? [pressed] são as teclas
  /// que a sessão aceitou nele: as que [allows] aceita, e as notas da melodia do
  /// passo que o acorde não aceita não entram (a nota de passagem não é do
  /// acorde, e a melodia já se cobra pelos ids). Se [satisfied] já vale com
  /// [pressed] vazio, o ataque não se cobra (o N.C., ou um ataque sem tempo), e
  /// quem monta os passos o deixa de fora.
  bool satisfied(Set<int> pressed);
}

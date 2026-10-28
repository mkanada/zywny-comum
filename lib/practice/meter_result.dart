// EX08: o resultado de um medidor, sem Flutter. O formato do curso (o `pass`
// e o `RoundResult`) o carrega, e a linha de comando lê esses arquivos.

import 'package:meta/meta.dart';

/// A % mínima dos trechos de dinâmica quando o `pass` pede `dynamics: true`
/// (EX08).
const double kDynamicsTarget = 80;

/// O resultado de um medidor: o número, a frase para a tela e os compassos
/// com problema (para o reforço). [passed] é `null` sem alvo ou sem dado.
@immutable
class MeterResult {
  const MeterResult({
    required this.id,
    required this.value,
    this.target,
    this.passed,
    required this.sentence,
    this.measures = const [],
  });

  final String id;

  /// O número do medidor; `NaN` quando não há o que medir.
  final double value;
  final double? target;
  final bool? passed;
  final String sentence;

  /// Compassos (ocorrência, 0 em diante) com problema.
  final List<int> measures;

  @override
  String toString() =>
      'MeterResult($id ${value.toStringAsFixed(1)}: $sentence)';
}

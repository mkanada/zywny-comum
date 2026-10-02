/// Frases dos resumos (U12): números de compasso e o tempo do aluno.
library;

import 'practice_report.dart';

/// "6", "6 e 8", "1, 4 e 9": junta [parts] em português.
String joinPt(List<String> parts) => switch (parts.length) {
  0 => '',
  1 => parts.single,
  _ => '${parts.sublist(0, parts.length - 1).join(', ')} e ${parts.last}',
};

/// Números de compasso em português. Com [ranges] (padrão), três ou mais
/// seguidos viram faixa: `[1, 2, 3, 6]` → "1 a 3 e 6". A lista é lida na
/// ordem dada; as faixas só se formam em sequência crescente de 1 em 1.
String joinMeasureNumbers(List<int> numbers, {bool ranges = true}) {
  if (!ranges) return joinPt([for (final n in numbers) '$n']);
  final parts = <String>[];
  var i = 0;
  while (i < numbers.length) {
    var j = i;
    while (j + 1 < numbers.length && numbers[j + 1] == numbers[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${numbers[i]} a ${numbers[j]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add('${numbers[k]}');
      }
    }
    i = j + 1;
  }
  return joinPt(parts);
}

/// Média (ms de parede) dentro da qual o aluno está "no tempo".
const kTimingOnBeatMs = 30.0;

/// Desvio-padrão (ms) acima do qual o pulso é "irregular".
const kTimingIrregularMs = 60.0;

/// Uma frase sobre o tempo do aluno, no lugar de milissegundos: "No tempo.",
/// "Você está entrando atrasado." ou "…adiantado.", mais "O pulso está
/// irregular." quando o desvio passa de [kTimingIrregularMs].
String practiceTimingPhrase(PracticeReport report) {
  final mean = report.meanDeltaMs;
  final base = mean.abs() <= kTimingOnBeatMs
      ? 'No tempo.'
      : (mean > 0
            ? 'Você está entrando atrasado.'
            : 'Você está entrando adiantado.');
  return report.stdDevMs > kTimingIrregularMs
      ? '$base O pulso está irregular.'
      : base;
}

// O veredito de uma nota tocada, sem Flutter: o núcleo do treino
// (`practice_session.dart`) e os juízes de tempo (EX10, `TimedJudge`) o usam,
// e a linha de comando carrega esses juízes. Mora aqui para que eles não
// puxem o `flutter/foundation` (o mesmo caminho do `expression_marks.dart`).

/// Como uma nota tocada se compara com o que a partitura esperava.
enum PracticeVerdictKind { correct, wrong, early, late, missed }

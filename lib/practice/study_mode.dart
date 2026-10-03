import 'practice_controller.dart' show PracticeMode;

/// Os quatro modos de estudo do treino livre, escolhidos num seletor só na
/// gaveta (U11). Por baixo continuam dois estados: se o treino está armado
/// (`_trainingMode`) e qual dos modos de treino vale (`PracticeMode`).
enum StudyMode {
  /// O app toca; o aluno acompanha.
  listen('Ouvir', 'O app toca; você acompanha.'),

  /// Modo espera (T02).
  wait('Espera', 'A música espera você acertar a nota.'),

  /// Tempo real (T03).
  realtime('Tempo real', 'A música não espera; cada nota é avaliada.');

  const StudyMode(this.label, this.explanation);

  final String label;
  final String explanation;

  /// O modo que o par (treino armado, modo de treino) significa.
  static StudyMode of({required bool training, required PracticeMode mode}) =>
      !training
      ? StudyMode.listen
      : switch (mode) {
          PracticeMode.wait => StudyMode.wait,
          PracticeMode.realtime => StudyMode.realtime,
        };

  /// `true` nos três modos de treino.
  bool get isTraining => this != StudyMode.listen;

  /// O modo de treino correspondente; `null` em [listen].
  PracticeMode? get practiceMode => switch (this) {
    StudyMode.listen => null,
    StudyMode.wait => PracticeMode.wait,
    StudyMode.realtime => PracticeMode.realtime,
  };
}

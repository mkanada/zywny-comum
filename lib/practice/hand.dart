/// Mão que o aluno escolhe tocar no modo treino (T02) — mesmo vocabulário do
/// painel de opções do mockup (`lib/mockup/practice_state.dart`), extraído
/// para cá porque `lib/main.dart` (app real) não deve depender de
/// `lib/mockup/` (tela solta, sem MIDI/áudio real). O mockup volta a
/// importar este enum em vez de definir o seu próprio.
///
/// Convenção de pauta (N03): piano, pauta 1 = mão direita, pauta 2 = mão
/// esquerda.
enum Hand { esquerda, direita, ambas }

extension HandStaves on Hand {
  /// Pautas que o aluno toca — o que [WaitModeSession.forStaves] espera.
  Set<int> get studentStaves => switch (this) {
    Hand.esquerda => const {2},
    Hand.direita => const {1},
    Hand.ambas => const {1, 2},
  };

  /// Pautas que o app toca (a outra mão). Vazio para "ambas": o app não
  /// toca nada, só o metrônomo (T04).
  Set<int> get appStaves => switch (this) {
    Hand.esquerda => const {1},
    Hand.direita => const {2},
    Hand.ambas => const {},
  };
}

extension HandLabel on Hand {
  String get label => switch (this) {
    Hand.esquerda => 'Esquerda',
    Hand.direita => 'Direita',
    Hand.ambas => 'Ambas',
  };

  /// Abreviação usada no botão da barra lateral (`Dir.` / `Esq.` / `Ambas`).
  String get shortLabel => switch (this) {
    Hand.esquerda => 'Esq.',
    Hand.direita => 'Dir.',
    Hand.ambas => 'Ambas',
  };
}

/// A regra dos 7 dias sem rede (D-NEG-OFFLINE) e o relógio do aparelho que
/// anda para trás.
///
/// A sessão guardada vale enquanto o servidor foi visto há pouco: a última
/// vez que o app falou com o Firebase (login, renovação do token) fica
/// gravada, e a sessão só é recusada depois de 7 dias sem conseguir renovar.
abstract final class SessionFreshness {
  /// Quantos dias a sessão guardada sobrevive sem rede.
  static const Duration window = Duration(days: 7);

  /// A chave das preferências onde fica a marca do "servidor visto".
  static const String lastVerifiedKey = 'auth_last_verified_ms';

  /// Verdadeiro quando a sessão guardada ainda pode ser usada.
  ///
  /// Não vale se o relógio do aparelho andou para trás: nesse caso o app não
  /// sabe que dia é, e a validade da licença (D-NEG-VALIDADE) fica sem
  /// chão — por isso a sessão é recusada.
  static bool isFresh(DateTime? lastVerified, DateTime now) {
    if (lastVerified == null) return false;
    if (now.isBefore(lastVerified)) return false;
    return now.difference(lastVerified) <= window;
  }

  /// A mensagem para a tela, conforme o caso.
  static String messageFor({
    required DateTime? lastVerified,
    required DateTime now,
  }) {
    if (lastVerified == null) {
      return 'Não achei nenhuma sessão guardada neste aparelho.';
    }
    if (now.isBefore(lastVerified)) {
      return 'O relógio do aparelho parece atrasado. Conecte-se à internet '
          'para confirmar seu acesso.';
    }
    return 'Faz mais de 7 dias sem conexão. Conecte-se à internet para renovar '
        'seu acesso.';
  }
}

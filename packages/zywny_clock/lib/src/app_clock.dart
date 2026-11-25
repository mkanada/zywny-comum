/// O relógio do app (CT05a). A hora do calendário, o tempo contínuo e os timers
/// saem daqui: quem lê a hora ou arma um timer recebe um [AppClock] pelo
/// construtor (`required`, sem padrão escondido). Não há relógio global.
abstract interface class AppClock {
  /// A data e a hora do calendário (meta diária, constância, minutos, aviso).
  DateTime now();

  /// O tempo contínuo, em segundos desde a origem do relógio (sessões, avisos,
  /// motorista, agendador). Nunca volta atrás.
  double get seconds;

  /// Um timer que dispara uma vez, [after] depois de agora. Um [after] negativo
  /// conta como zero.
  AppTimer timer(Duration after, void Function() callback);

  /// Um timer que dispara a cada [every], a começar [every] depois de agora. O
  /// [callback] recebe o próprio timer, para ler o `tick` ou cancelá-lo.
  /// [every] tem de ser positivo.
  AppTimer periodic(Duration every, void Function(AppTimer) callback);
}

/// Um timer criado por um [AppClock]. Cancelar é seguro a qualquer momento,
/// inclusive dentro do próprio callback, e cancelar de novo não faz nada.
abstract interface class AppTimer {
  /// Para o timer: ele não dispara mais.
  void cancel();

  /// Ainda vai disparar: não foi cancelado e, se é um `timer` de uma vez, ainda
  /// não disparou.
  bool get isActive;

  /// Quantas vezes o timer disparou: 0 antes do primeiro disparo, 1 depois de um
  /// `timer` de uma vez, e 1, 2, 3… num periódico.
  int get tick;
}

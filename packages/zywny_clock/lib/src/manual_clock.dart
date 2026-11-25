import 'app_clock.dart';
import 'timer_rules.dart';

/// Um relógio que só anda quando alguém manda: [advance] avança o tempo, e os
/// timers vencidos disparam nele, na ordem do vencimento (e, empatados, na ordem
/// em que foram criados).
///
/// Durante o disparo de um timer, [now] e [seconds] valem o instante dele, como
/// se ele tivesse disparado naquela hora. Um timer criado dentro de um callback
/// conta a partir desse instante e dispara dentro do mesmo [advance] se vencer
/// antes do fim dele. Um erro num callback sai do [advance]: o relógio fica no
/// instante do timer que falhou, e os outros timers continuam pendentes.
final class ManualClock implements AppClock {
  /// Começa em [inicio]: é a hora de calendário que [now] devolve no começo.
  ManualClock(DateTime inicio) : _inicio = inicio;

  final DateTime _inicio;
  final List<_ManualTimer> _timers = [];
  Duration _decorrido = Duration.zero;
  int _ordem = 0;
  bool _avancando = false;

  /// O tempo que passou desde a criação: o instante atual do relógio.
  Duration get elapsed => _decorrido;

  @override
  DateTime now() => _inicio.add(_decorrido);

  @override
  double get seconds =>
      _decorrido.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  AppTimer timer(Duration after, void Function() callback) =>
      _agendar(tempoDoTimer(after), null, (_) => callback());

  @override
  AppTimer periodic(Duration every, void Function(AppTimer) callback) {
    verificarPeriodo(every);
    return _agendar(every, every, callback);
  }

  /// Anda [d] para a frente e dispara os timers que vencem até lá. Um [d] igual
  /// a zero só dispara o que já venceu.
  void advance(Duration d) {
    if (d.isNegative) {
      throw ArgumentError.value(d, 'd', 'o relógio não volta atrás');
    }
    if (_avancando) {
      throw StateError('advance chamado de dentro de um disparo deste relógio');
    }
    final alvo = _decorrido + d;
    _avancando = true;
    try {
      while (true) {
        final proximo = _proximo(alvo);
        if (proximo == null) break;
        _decorrido = proximo._vence;
        proximo._disparar();
      }
      _decorrido = alvo;
    } finally {
      _avancando = false;
    }
  }

  /// Os timers que ainda vão disparar, do que vence primeiro para o que vence
  /// depois. Para os testes.
  List<AppTimer> get pendingTimers {
    final ordenados = [..._timers]..sort(_ordemDeDisparo);
    return List.unmodifiable(ordenados);
  }

  _ManualTimer _agendar(
    Duration apos,
    Duration? periodo,
    void Function(AppTimer) callback,
  ) {
    final timer = _ManualTimer._(
      this,
      _decorrido + apos,
      periodo,
      callback,
      ++_ordem,
    );
    _timers.add(timer);
    return timer;
  }

  /// O timer que vence primeiro até [alvo], ou null se nenhum venceu.
  _ManualTimer? _proximo(Duration alvo) {
    _ManualTimer? primeiro;
    for (final timer in _timers) {
      if (timer._vence > alvo) continue;
      if (primeiro == null || _ordemDeDisparo(timer, primeiro) < 0) {
        primeiro = timer;
      }
    }
    return primeiro;
  }

  static int _ordemDeDisparo(_ManualTimer a, _ManualTimer b) {
    final porVencimento = a._vence.compareTo(b._vence);
    return porVencimento != 0 ? porVencimento : a._ordem.compareTo(b._ordem);
  }

  void _retirar(_ManualTimer timer) => _timers.remove(timer);

  int _proximaOrdem() => ++_ordem;
}

/// O timer do [ManualClock]. Não tem relógio próprio: guarda o instante do
/// próximo disparo e a ordem de criação, e o relógio decide quando ele dispara.
final class _ManualTimer implements AppTimer {
  _ManualTimer._(
    this._relogio,
    this._vence,
    this._periodo,
    this._callback,
    this._ordem,
  );

  final ManualClock _relogio;
  final Duration? _periodo;
  final void Function(AppTimer) _callback;
  Duration _vence;
  int _ordem;
  int _tick = 0;
  bool _ativo = true;

  @override
  void cancel() {
    if (!_ativo) return;
    _ativo = false;
    _relogio._retirar(this);
  }

  @override
  bool get isActive => _ativo;

  @override
  int get tick => _tick;

  /// Dispara. O relógio já está no instante [_vence]. O próximo disparo do
  /// periódico é marcado antes do callback, e um cancelamento dentro dele o tira
  /// da lista.
  void _disparar() {
    _tick++;
    final periodo = _periodo;
    if (periodo == null) {
      _ativo = false;
      _relogio._retirar(this);
    } else {
      _vence += periodo;
      _ordem = _relogio._proximaOrdem();
    }
    _callback(this);
  }
}

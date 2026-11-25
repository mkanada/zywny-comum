import 'dart:async';

import 'app_clock.dart';
import 'timer_rules.dart';

/// O relógio de verdade: [now] é o `DateTime.now`, [seconds] lê um [Stopwatch]
/// que começa na criação, e os timers são os `Timer` do Dart.
final class SystemClock implements AppClock {
  SystemClock() : _cronometro = Stopwatch()..start();

  final Stopwatch _cronometro;

  @override
  DateTime now() => DateTime.now();

  @override
  double get seconds =>
      _cronometro.elapsedMicroseconds / Duration.microsecondsPerSecond;

  @override
  AppTimer timer(Duration after, void Function() callback) {
    final timer = _SystemTimer();
    timer._dart = Timer(tempoDoTimer(after), () {
      timer._disparou();
      callback();
    });
    return timer;
  }

  @override
  AppTimer periodic(Duration every, void Function(AppTimer) callback) {
    verificarPeriodo(every);
    final timer = _SystemTimer();
    timer._dart = Timer.periodic(every, (_) {
      timer._tick++;
      callback(timer);
    });
    return timer;
  }
}

/// O timer do [SystemClock]: embrulha o `Timer` do Dart para contar os disparos e
/// dizer se ainda vai disparar.
final class _SystemTimer implements AppTimer {
  late final Timer _dart;
  int _tick = 0;
  bool _ativo = true;

  @override
  void cancel() {
    _ativo = false;
    _dart.cancel();
  }

  @override
  bool get isActive => _ativo;

  @override
  int get tick => _tick;

  /// Um `timer` de uma vez: depois do disparo ele não vai mais disparar.
  void _disparou() {
    _tick++;
    _ativo = false;
  }
}

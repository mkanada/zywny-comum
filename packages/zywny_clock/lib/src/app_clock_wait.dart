import 'dart:async';

import 'app_clock.dart';

/// A espera do `Future.delayed`, sobre o relógio do app (CT05f): quem espera
/// recebe o [AppClock] pelo construtor, e com um `ManualClock` a espera só acaba
/// quando o teste anda o relógio.
extension AppClockWait on AppClock {
  /// Completa [after] depois de agora, no relógio (um [after] zero ou negativo
  /// completa no próximo disparo, como o [timer]: com o `ManualClock`, no
  /// próximo `advance`).
  Future<void> wait(Duration after) {
    final pronto = Completer<void>();
    timer(after, pronto.complete);
    return pronto.future;
  }
}

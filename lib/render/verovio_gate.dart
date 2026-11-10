import 'dart:async';
import 'dart:collection';

import 'verovio_cores_stub.dart'
    if (dart.library.io) 'verovio_cores_io.dart'
    as cores;

/// O portão das chamadas nativas ao Verovio (leitura e desenho). Antes era uma
/// fila de uma vaga só, porque o Verovio guardava estado global (as globais do
/// `ioabc.cpp`, para ABC, ainda são). O estado de ids do Verovio deste projeto
/// é `thread_local`, então MusicXML, MEI e `.mxl` podem ler em paralelo, cada um
/// no seu isolate; o que não é seguro (ABC) pede [exclusive] e roda sozinho.
///
/// Com [parallelism] 1 (o padrão) é a fila de antes: uma chamada por vez, na
/// ordem de chegada. Quem mede muitas músicas de uma vez (o catálogo de T18)
/// sobe o número enquanto mede e o devolve depois.
class VerovioGate {
  /// Quantas chamadas seguras rodam ao mesmo tempo.
  int parallelism = 1;

  final Queue<_Waiter> _waiting = Queue();
  int _running = 0;
  bool _exclusiveRunning = false;

  /// Roda [job] quando houver vaga. [exclusive]: só quando nada mais roda, e nada
  /// mais roda enquanto ele não acaba.
  Future<T> run<T>(Future<T> Function() job, {bool exclusive = false}) async {
    final waiter = _Waiter(exclusive);
    _waiting.add(waiter);
    _pump();
    await waiter.start.future;
    try {
      return await job();
    } finally {
      _running--;
      _exclusiveRunning = false;
      _pump();
    }
  }

  void _pump() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.first;
      final free = next.exclusive
          ? _running == 0
          : !_exclusiveRunning && _running < parallelism;
      if (!free) return;
      _waiting.removeFirst();
      _running++;
      if (next.exclusive) _exclusiveRunning = true;
      next.start.complete();
    }
  }
}

class _Waiter {
  _Waiter(this.exclusive);

  final bool exclusive;
  final start = Completer<void>();
}

/// O portão de todo o app.
final VerovioGate verovioGate = VerovioGate();

/// Quantas leituras seguras em paralelo valem a pena neste aparelho: os núcleos
/// menos um (o da interface), de 1 a 4. Na Web, 1 (um worker só).
int defaultVerovioParallelism() => cores.verovioCores().clamp(2, 5) - 1;

/// Só o que o Verovio lê sem estado global compartilhado roda em paralelo; o
/// resto (ABC, formato que ele adivinha pelo conteúdo) passa sozinho.
bool verovioSafeInParallel(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.musicxml') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.mxl') ||
      lower.endsWith('.mei');
}

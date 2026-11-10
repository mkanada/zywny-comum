import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/render/verovio_gate.dart';

void main() {
  /// Roda [n] chamadas que ficam abertas até o [release] e diz o máximo que
  /// estiveram abertas juntas.
  Future<int> peak(
    VerovioGate gate,
    int n, {
    List<bool> exclusive = const [],
  }) async {
    var open = 0;
    var peak = 0;
    final release = Completer<void>();
    final jobs = [
      for (var i = 0; i < n; i++)
        gate.run(() async {
          open++;
          if (open > peak) peak = open;
          await release.future;
          open--;
        }, exclusive: i < exclusive.length && exclusive[i]),
    ];
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait(jobs);
    return peak;
  }

  test('com 1 vaga é a fila de antes', () async {
    expect(await peak(VerovioGate(), 5), 1);
  });

  test('com N vagas, N ao mesmo tempo', () async {
    expect(await peak(VerovioGate()..parallelism = 3, 8), 3);
  });

  test('o exclusivo roda sozinho', () async {
    final gate = VerovioGate()..parallelism = 4;
    final log = <String>[];
    final release = Completer<void>();
    Future<void> job(String name, {bool exclusive = false}) =>
        gate.run(() async {
          log.add('$name+');
          await release.future;
          log.add('$name-');
        }, exclusive: exclusive);

    final all = [job('a'), job('b'), job('x', exclusive: true), job('c')];
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait(all);
    // a e b juntos; x só depois dos dois e sozinho; c só depois de x.
    expect(log.indexOf('x+'), greaterThan(log.indexOf('a-')));
    expect(log.indexOf('x+'), greaterThan(log.indexOf('b-')));
    expect(log.indexOf('c+'), greaterThan(log.indexOf('x-')));
  });

  test('uma chamada que falha libera a vaga', () async {
    final gate = VerovioGate();
    await expectLater(
      gate.run<void>(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(await gate.run(() async => 7), 7);
  });

  test('só o que o Verovio lê sem estado global é seguro em paralelo', () {
    expect(verovioSafeInParallel('/t/001.musicxml'), isTrue);
    expect(verovioSafeInParallel('/t/A.MXL'), isTrue);
    expect(verovioSafeInParallel('/t/a.mei'), isTrue);
    expect(verovioSafeInParallel('/t/a.abc'), isFalse);
    expect(verovioSafeInParallel('/t/score'), isFalse);
  });
}

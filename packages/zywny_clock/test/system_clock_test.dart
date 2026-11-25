import 'dart:async';

import 'package:test/test.dart';
import 'package:zywny_clock/zywny_clock.dart';

// Testes básicos do SystemClock: o tempo é de verdade, então as esperas são
// curtas e com folga, e nenhuma conta depende de um instante exato.
void main() {
  _relogioDeParede();
  _timersDeUmaVez();
  _periodico();
}

void _relogioDeParede() {
  group('SystemClock: hora e tempo', () {
    test('now é a hora do sistema', () {
      final relogio = SystemClock();

      final antes = DateTime.now();
      final agora = relogio.now();
      final depois = DateTime.now();

      expect(agora.isBefore(antes), isFalse);
      expect(agora.isAfter(depois), isFalse);
    });

    test('seconds começa perto de zero e não volta atrás', () async {
      final relogio = SystemClock();
      final primeiro = relogio.seconds;

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final segundo = relogio.seconds;

      expect(primeiro, greaterThanOrEqualTo(0));
      expect(primeiro, lessThan(1));
      expect(segundo, greaterThan(primeiro));
    });
  });
}

void _timersDeUmaVez() {
  group('SystemClock: timer de uma vez', () {
    test('dispara depois do atraso, uma vez só', () async {
      final relogio = SystemClock();
      final disparo = Completer<void>();
      var disparos = 0;

      final t = relogio.timer(const Duration(milliseconds: 10), () {
        disparos++;
        disparo.complete();
      });
      await disparo.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(disparos, 1);
      expect(t.tick, 1);
      expect(t.isActive, isFalse);
    });

    test('um timer cancelado não dispara', () async {
      final relogio = SystemClock();
      var disparos = 0;

      final t =
          relogio.timer(const Duration(milliseconds: 10), () => disparos++);
      t.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(disparos, 0);
      expect(t.isActive, isFalse);
    });

    test('um atraso negativo dispara como zero', () async {
      final relogio = SystemClock();
      final disparo = Completer<void>();

      relogio.timer(const Duration(milliseconds: -10), disparo.complete);

      await disparo.future;
      expect(disparo.isCompleted, isTrue);
    });
  });
}

void _periodico() {
  group('SystemClock: periódico', () {
    test('dispara várias vezes e para quando cancelado no callback', () async {
      final relogio = SystemClock();
      final parou = Completer<void>();
      final ticks = <int>[];

      late final AppTimer t;
      t = relogio.periodic(const Duration(milliseconds: 5), (_) {
        ticks.add(t.tick);
        if (t.tick == 3) {
          t.cancel();
          parou.complete();
        }
      });
      await parou.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(ticks, [1, 2, 3]);
      expect(t.isActive, isFalse);
    });

    test('intervalo zero ou negativo é erro', () {
      final relogio = SystemClock();

      expect(
        () => relogio.periodic(Duration.zero, (_) {}),
        throwsArgumentError,
      );
      expect(
        () => relogio.periodic(const Duration(milliseconds: -5), (_) {}),
        throwsArgumentError,
      );
    });
  });
}

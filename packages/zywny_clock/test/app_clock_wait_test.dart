import 'package:test/test.dart';
import 'package:zywny_clock/zywny_clock.dart';

// O `wait` do AppClock (CT05f): a espera acaba quando o relógio anda o atraso,
// no ManualClock; um atraso zero ou negativo acaba no próximo advance.
void main() {
  group('AppClock.wait', () {
    test('só completa quando o relógio anda o atraso inteiro', () async {
      final relogio = ManualClock(DateTime(2026, 11, 25, 10));
      var pronto = false;
      final espera = relogio
          .wait(const Duration(milliseconds: 450))
          .then((_) => pronto = true);

      relogio.advance(const Duration(milliseconds: 449));
      await Future<void>.delayed(Duration.zero);
      expect(pronto, isFalse);

      relogio.advance(const Duration(milliseconds: 1));
      await espera;
      expect(pronto, isTrue);
    });

    test('um atraso zero ou negativo completa no próximo advance, nunca na '
        'criação', () async {
      final relogio = ManualClock(DateTime(2026, 11, 25, 10));
      var zero = false;
      var negativo = false;
      relogio.wait(Duration.zero).then((_) => zero = true);
      relogio.wait(const Duration(seconds: -1)).then((_) => negativo = true);

      await Future<void>.delayed(Duration.zero);
      expect(zero || negativo, isFalse);

      relogio.advance(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(zero, isTrue);
      expect(negativo, isTrue);
    });
  });
}

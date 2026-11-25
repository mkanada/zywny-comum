import 'package:test/test.dart';
import 'package:zywny_clock/zywny_clock.dart';

// Os testes do ManualClock, em partes (o `main` só chama as partes, como nos
// outros pacotes do comum: `just qualidade` mede as funções).
void main() {
  _tempo();
  _timerDisparo();
  _timerOrdem();
  _timerFim();
  _timerCancelar();
  _periodico();
  _periodicoCancelar();
  _periodicoPorTempo();
  _pendentes();
  _regras();
}

final _inicio = DateTime(2026, 11, 25, 10);

void _tempo() {
  group('tempo', () {
    test('começa na data dada, em zero segundos, sem timers', () {
      final relogio = ManualClock(_inicio);

      expect(relogio.now(), _inicio);
      expect(relogio.seconds, 0);
      expect(relogio.elapsed, Duration.zero);
      expect(relogio.pendingTimers, isEmpty);
    });

    test('só anda com advance, e now e seconds acompanham', () {
      final relogio = ManualClock(_inicio);

      relogio.advance(const Duration(milliseconds: 1500));

      expect(relogio.now(), _inicio.add(const Duration(milliseconds: 1500)));
      expect(relogio.seconds, 1.5);
      expect(relogio.elapsed, const Duration(milliseconds: 1500));
    });

    test('advance somado é igual a um advance só', () {
      final relogio = ManualClock(_inicio);

      for (var i = 0; i < 1000; i++) {
        relogio.advance(const Duration(milliseconds: 4));
      }

      expect(relogio.seconds, 4);
      expect(relogio.now(), _inicio.add(const Duration(seconds: 4)));
    });

    test('advance de zero não muda nada', () {
      final relogio = ManualClock(_inicio)
        ..advance(const Duration(seconds: 2));

      relogio.advance(Duration.zero);

      expect(relogio.seconds, 2);
    });

    test('advance negativo é erro e não mexe no relógio', () {
      final relogio = ManualClock(_inicio)
        ..advance(const Duration(seconds: 2));

      expect(
        () => relogio.advance(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
      expect(relogio.seconds, 2);
    });
  });
}

void _timerDisparo() {
  group('timer de uma vez: disparo', () {
    test('não dispara sem advance, nem ao ser criado', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;

      relogio.timer(const Duration(seconds: 1), () => disparos++);

      expect(disparos, 0);
      expect(relogio.pendingTimers, hasLength(1));
    });

    test('dispara quando o advance chega exatamente ao vencimento', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      final t = relogio.timer(const Duration(seconds: 1), () => disparos++);

      relogio.advance(const Duration(milliseconds: 999));
      expect(disparos, 0);
      expect(t.isActive, isTrue);
      expect(t.tick, 0);

      relogio.advance(const Duration(milliseconds: 1));
      expect(disparos, 1);
      expect(t.isActive, isFalse);
      expect(t.tick, 1);
    });

    test('dispara uma vez só, mesmo que o tempo passe muito depois', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      relogio.timer(const Duration(milliseconds: 100), () => disparos++);

      relogio.advance(const Duration(hours: 1));
      relogio.advance(const Duration(hours: 1));

      expect(disparos, 1);
      expect(relogio.pendingTimers, isEmpty);
    });

    test('durante o disparo, now e seconds valem o instante do timer', () {
      final relogio = ManualClock(_inicio);
      DateTime? agora;
      double? segundos;
      relogio.timer(const Duration(milliseconds: 250), () {
        agora = relogio.now();
        segundos = relogio.seconds;
      });

      relogio.advance(const Duration(seconds: 3));

      expect(agora, _inicio.add(const Duration(milliseconds: 250)));
      expect(segundos, 0.25);
      expect(relogio.seconds, 3);
    });
  });
}

void _timerOrdem() {
  group('timer de uma vez: ordem', () {
    test('dispara na ordem do vencimento, não na da criação', () {
      final relogio = ManualClock(_inicio);
      final ordem = <String>[];
      relogio.timer(const Duration(milliseconds: 300), () => ordem.add('c'));
      relogio.timer(const Duration(milliseconds: 100), () => ordem.add('a'));
      relogio.timer(const Duration(milliseconds: 200), () => ordem.add('b'));

      relogio.advance(const Duration(seconds: 1));

      expect(ordem, ['a', 'b', 'c']);
    });

    test('empatados disparam na ordem em que foram criados', () {
      final relogio = ManualClock(_inicio);
      final ordem = <int>[];
      for (var i = 0; i < 5; i++) {
        relogio.timer(const Duration(seconds: 1), () => ordem.add(i));
      }

      relogio.advance(const Duration(seconds: 1));

      expect(ordem, [0, 1, 2, 3, 4]);
    });

    test('cada callback vê o próprio instante, não o do fim do advance', () {
      final relogio = ManualClock(_inicio);
      final instantes = <double>[];
      relogio.timer(const Duration(milliseconds: 500), () {
        instantes.add(relogio.seconds);
      });
      relogio.timer(const Duration(milliseconds: 100), () {
        instantes.add(relogio.seconds);
      });

      relogio.advance(const Duration(seconds: 2));

      expect(instantes, [0.1, 0.5]);
    });

    test('um timer criado dentro de um callback conta a partir do instante dele', () {
      final relogio = ManualClock(_inicio);
      final disparos = <double>[];
      relogio.timer(const Duration(milliseconds: 100), () {
        disparos.add(relogio.seconds);
        relogio.timer(const Duration(milliseconds: 50), () {
          disparos.add(relogio.seconds);
        });
      });

      relogio.advance(const Duration(milliseconds: 300));

      expect(disparos, [0.1, 0.15]);
    });
  });
}

void _timerFim() {
  group('timer de uma vez: atrasos especiais', () {
    test('um timer criado no callback que vence depois do fim não dispara', () {
      final relogio = ManualClock(_inicio);
      var tardio = 0;
      relogio.timer(const Duration(milliseconds: 100), () {
        relogio.timer(const Duration(seconds: 10), () => tardio++);
      });

      relogio.advance(const Duration(seconds: 1));
      expect(tardio, 0);
      expect(relogio.pendingTimers, hasLength(1));

      relogio.advance(const Duration(seconds: 10));
      expect(tardio, 1);
    });

    test('um atraso de zero dispara no próximo advance, nunca na criação', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;

      relogio.timer(Duration.zero, () => disparos++);
      expect(disparos, 0);

      relogio.advance(Duration.zero);
      expect(disparos, 1);
    });

    test('um atraso negativo conta como zero', () {
      final relogio = ManualClock(_inicio)
        ..advance(const Duration(seconds: 5));
      var disparos = 0;

      relogio.timer(const Duration(seconds: -3), () => disparos++);
      relogio.advance(Duration.zero);

      expect(disparos, 1);
    });
  });
}

void _timerCancelar() {
  group('timer de uma vez: cancelar', () {
    test('cancel antes do vencimento impede o disparo', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      final t = relogio.timer(const Duration(seconds: 1), () => disparos++);

      t.cancel();
      relogio.advance(const Duration(seconds: 5));

      expect(disparos, 0);
      expect(t.isActive, isFalse);
      expect(t.tick, 0);
      expect(relogio.pendingTimers, isEmpty);
    });

    test('cancel de novo não faz nada, e cancel depois do disparo também não', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      final cancelado =
          relogio.timer(const Duration(seconds: 1), () => disparos++);
      final disparado =
          relogio.timer(const Duration(milliseconds: 10), () => disparos++);

      cancelado.cancel();
      cancelado.cancel();
      relogio.advance(const Duration(seconds: 2));
      disparado.cancel();

      expect(disparos, 1);
      expect(disparado.tick, 1);
    });

    test('um timer cancelado pelo callback de outro não dispara no mesmo advance', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      late final AppTimer depois;
      relogio.timer(const Duration(milliseconds: 100), () => depois.cancel());
      depois =
          relogio.timer(const Duration(milliseconds: 200), () => disparos++);

      relogio.advance(const Duration(seconds: 1));

      expect(disparos, 0);
      expect(depois.isActive, isFalse);
    });
  });
}

void _periodico() {
  group('periódico', () {
    test('dispara a cada intervalo, com o tick subindo', () {
      final relogio = ManualClock(_inicio);
      final ticks = <int>[];
      final instantes = <double>[];
      relogio.periodic(const Duration(milliseconds: 100), (t) {
        ticks.add(t.tick);
        instantes.add(relogio.seconds);
      });

      relogio.advance(const Duration(milliseconds: 350));

      expect(ticks, [1, 2, 3]);
      expect(instantes, [0.1, 0.2, 0.3]);
    });

    test('o tick do timer vale durante e depois dos disparos', () {
      final relogio = ManualClock(_inicio);
      late final AppTimer t;
      final vistos = <int>[];
      t = relogio.periodic(const Duration(milliseconds: 100), (_) {
        vistos.add(t.tick);
      });

      expect(t.tick, 0);
      relogio.advance(const Duration(milliseconds: 250));

      expect(vistos, [1, 2]);
      expect(t.tick, 2);
      expect(t.isActive, isTrue);
    });

    test('sem deriva: avanços quebrados caem nos mesmos instantes', () {
      final relogio = ManualClock(_inicio);
      final instantes = <double>[];
      relogio.periodic(const Duration(milliseconds: 100), (_) {
        instantes.add(relogio.seconds);
      });

      for (var i = 0; i < 30; i++) {
        relogio.advance(const Duration(milliseconds: 37));
      }

      expect(instantes.length, 11);
      expect(instantes, [for (var i = 1; i <= 11; i++) i / 10]);
    });
  });
}

void _periodicoCancelar() {
  group('periódico: cancelar', () {
    test('cancel dentro do callback para no disparo que o pediu', () {
      final relogio = ManualClock(_inicio);
      late final AppTimer t;
      var disparos = 0;
      t = relogio.periodic(const Duration(milliseconds: 100), (_) {
        disparos++;
        if (disparos == 2) t.cancel();
      });

      relogio.advance(const Duration(seconds: 5));

      expect(disparos, 2);
      expect(t.tick, 2);
      expect(t.isActive, isFalse);
      expect(relogio.pendingTimers, isEmpty);
    });

    test('cancel de fora para o periódico', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      final t = relogio.periodic(
        const Duration(milliseconds: 100),
        (_) => disparos++,
      );

      relogio.advance(const Duration(milliseconds: 250));
      t.cancel();
      relogio.advance(const Duration(seconds: 5));

      expect(disparos, 2);
      expect(t.isActive, isFalse);
    });
  });
}

void _periodicoPorTempo() {
  group('periódico: intervalo e volume', () {
    test('um timer criado no callback de um periódico dispara no tempo certo', () {
      final relogio = ManualClock(_inicio);
      final marcas = <String>[];
      relogio.periodic(const Duration(milliseconds: 100), (t) {
        marcas.add('p${t.tick}');
        if (t.tick == 1) {
          relogio.timer(const Duration(milliseconds: 50), () => marcas.add('t'));
        }
      });

      relogio.advance(const Duration(milliseconds: 250));

      expect(marcas, ['p1', 't', 'p2']);
    });

    test('intervalo zero ou negativo é erro', () {
      final relogio = ManualClock(_inicio);

      expect(
        () => relogio.periodic(Duration.zero, (_) {}),
        throwsArgumentError,
      );
      expect(
        () => relogio.periodic(const Duration(milliseconds: -1), (_) {}),
        throwsArgumentError,
      );
      expect(relogio.pendingTimers, isEmpty);
    });

    test('muitos disparos seguidos andam bem (4 ms por passo, 60 s)', () {
      final relogio = ManualClock(_inicio);
      var disparos = 0;
      relogio.periodic(const Duration(milliseconds: 4), (_) => disparos++);

      for (var i = 0; i < 60000; i++) {
        relogio.advance(const Duration(milliseconds: 1));
      }

      expect(disparos, 15000);
    });
  });
}

void _pendentes() {
  group('pendingTimers', () {
    test('lista só os que vão disparar, do que vence primeiro para o último', () {
      final relogio = ManualClock(_inicio);
      final longe = relogio.timer(const Duration(seconds: 9), () {});
      final perto = relogio.timer(const Duration(seconds: 1), () {});
      final cancelado = relogio.timer(const Duration(seconds: 2), () {});
      cancelado.cancel();

      expect(relogio.pendingTimers, [perto, longe]);
    });

    test('a lista devolvida não muda o relógio', () {
      final relogio = ManualClock(_inicio);
      relogio.timer(const Duration(seconds: 1), () {});

      final lista = relogio.pendingTimers;

      expect(() => lista.clear(), throwsUnsupportedError);
      expect(relogio.pendingTimers, hasLength(1));
    });

    test('um periódico continua na lista até ser cancelado', () {
      final relogio = ManualClock(_inicio);
      final t = relogio.periodic(const Duration(seconds: 1), (_) {});

      relogio.advance(const Duration(seconds: 10));

      expect(relogio.pendingTimers, [t]);
    });
  });
}

void _regras() {
  group('regras de uso', () {
    test('advance dentro de um callback é erro', () {
      final relogio = ManualClock(_inicio);
      Object? erro;
      relogio.timer(const Duration(milliseconds: 10), () {
        try {
          relogio.advance(const Duration(seconds: 1));
        } on Object catch (e) {
          erro = e;
        }
      });

      relogio.advance(const Duration(seconds: 1));

      expect(erro, isStateError);
      expect(relogio.seconds, 1);
    });

    test('um erro num callback sai do advance, e o relógio segue depois', () {
      final relogio = ManualClock(_inicio);
      var depois = 0;
      relogio.timer(const Duration(milliseconds: 100), () {
        throw StateError('falhou de propósito');
      });
      relogio.timer(const Duration(milliseconds: 200), () => depois++);

      expect(
        () => relogio.advance(const Duration(seconds: 1)),
        throwsStateError,
      );
      expect(relogio.seconds, 0.1);
      expect(depois, 0);

      relogio.advance(const Duration(seconds: 1));
      expect(depois, 1);
      expect(relogio.seconds, closeTo(1.1, 1e-9));
    });
  });
}

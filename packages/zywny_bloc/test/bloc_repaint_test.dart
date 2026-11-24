import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

/// Fonte de estado falsa: conta quando alguém assina e cancela o stream.
class _FakeSource implements StateStreamable<int> {
  _FakeSource() {
    _controller = StreamController<int>.broadcast(
      sync: true,
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }

  late final StreamController<int> _controller;
  int listens = 0;
  int cancels = 0;

  @override
  int state = 0;

  @override
  Stream<int> get stream => _controller.stream;

  void emit(int next) {
    state = next;
    _controller.add(next);
  }
}

class _Counter extends Cubit<int> {
  _Counter() : super(0);

  void increment() => emit(state + 1);
}

void main() {
  _grupoAssinatura();
  _grupoAvisos();
  _grupoOuvintes();
}

/// Quando a fonte é assinada e quando a assinatura é cancelada.
void _grupoAssinatura() {
  group('BlocRepaint assina a fonte', () {
    test('assina o stream com o primeiro ouvinte e cancela com o último', () {
      final source = _FakeSource();
      final repaint = BlocRepaint(source);
      void a() {}
      void b() {}

      expect(source.listens, 0, reason: 'sem ouvinte, não assina');

      repaint.addListener(a);
      expect(source.listens, 1);
      repaint.addListener(b);
      expect(source.listens, 1, reason: 'o segundo ouvinte não assina de novo');

      repaint.removeListener(a);
      expect(source.cancels, 0, reason: 'ainda há um ouvinte');
      repaint.removeListener(b);
      expect(source.cancels, 1, reason: 'saiu o último: cancela');

      repaint.addListener(a);
      expect(source.listens, 2, reason: 'volta a assinar com um novo ouvinte');
      repaint.dispose();
    });

    test('dispose cancela a assinatura e nenhum aviso sai depois', () {
      final source = _FakeSource();
      final repaint = BlocRepaint(source);
      var avisos = 0;
      void ouvinte() => avisos++;
      repaint.addListener(ouvinte);

      repaint.dispose();
      expect(source.cancels, 1);

      source.emit(1);
      expect(avisos, 0);
    });
  });
}

/// Quais estados avisam os ouvintes.
void _grupoAvisos() {
  group('BlocRepaint avisa os ouvintes', () {
    test('avisa os ouvintes a cada estado novo do Cubit', () async {
      final cubit = _Counter();
      addTearDown(cubit.close);
      final repaint = BlocRepaint(cubit);
      var avisos = 0;
      void ouvinte() => avisos++;
      repaint.addListener(ouvinte);

      cubit.increment();
      cubit.increment();
      cubit.increment();
      await pumpEventQueue();

      expect(avisos, 3);
      expect(cubit.state, 3, reason: 'o pintor lê o estado, não o aviso');
      repaint.dispose();
    });

    test(
      'when decide quais estados avisam, com o estado anterior certo',
      () async {
        final cubit = _Counter();
        addTearDown(cubit.close);
        final pares = <(int, int)>[];
        final repaint = BlocRepaint<int>(
          cubit,
          when: (anterior, novo) {
            pares.add((anterior, novo));
            return novo.isEven;
          },
        );
        var avisos = 0;
        void ouvinte() => avisos++;
        repaint.addListener(ouvinte);

        for (var i = 0; i < 4; i++) {
          cubit.increment();
        }
        await pumpEventQueue();

        expect(pares, [(0, 1), (1, 2), (2, 3), (3, 4)]);
        expect(avisos, 2, reason: 'só os pares 2 e 4 avisam');
        repaint.dispose();
      },
    );
  });
}

/// Um ouvinte que sai durante o aviso não atrapalha os outros.
void _grupoOuvintes() {
  group('BlocRepaint ouvintes', () {
    test('um ouvinte pode sair durante o aviso sem quebrar os outros', () {
      final source = _FakeSource();
      final repaint = BlocRepaint(source);
      final chamados = <String>[];
      void primeiro() {
        chamados.add('primeiro');
        repaint.removeListener(primeiro);
      }

      void segundo() => chamados.add('segundo');
      repaint.addListener(primeiro);
      repaint.addListener(segundo);

      source.emit(1);
      source.emit(2);

      expect(chamados, ['primeiro', 'segundo', 'segundo']);
      repaint.dispose();
    });
  });
}

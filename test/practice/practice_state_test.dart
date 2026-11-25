// BL28: o estado da prática (`PracticeState`, que a tela e o motor leem) e a
// fatia de um campo dele (`PracticeField`, que o teclado e a escada leem, como
// `StateStreamable`, sem a prática inteira).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_comum/practice/practice_controller.dart';

/// Uma fonte de estado que o teste muda com [mudar] (o `emit` é protegido).
class _Fonte extends Cubit<PracticeState> {
  _Fonte(super.initial);

  void mudar(PracticeState estado) => emit(estado);
}

RepeatStatus _escada() => RepeatStatus(
  measure: 2,
  rung: const RepeatRung.wait(),
  rungIndex: 0,
  rungCount: 2,
);

void main() {
  _estado();
  _campo();
}

void _estado() {
  group('PracticeState', () {
    test('copyWith troca só o campo pedido', () {
      const estado = PracticeState(correctCount: 2);
      final novo = estado.copyWith(wrongCount: 1);

      expect(novo.correctCount, 2);
      expect(novo.wrongCount, 1);
      expect(novo.wrongPitches, isEmpty);
      expect(novo.liveScore, (hits: 0, total: 0));
    });

    test('a escada só some com semRepeat; sem ele, fica', () {
      final escada = _escada();
      final com = const PracticeState().copyWith(repeat: escada);

      expect(com.repeat, same(escada));
      expect(com.copyWith(correctCount: 1).repeat, same(escada));
      expect(com.copyWith(semRepeat: true).repeat, isNull);
    });

    test('é igual pelo valor; a escada compara pela instância', () {
      expect(
        const PracticeState(wrongPitches: {60}),
        equals(const PracticeState(wrongPitches: {60})),
      );
      expect(
        const PracticeState(wrongPitches: {60}),
        isNot(equals(const PracticeState(wrongPitches: {61}))),
      );
      // Dois `RepeatStatus` com os mesmos valores são estados diferentes: cada
      // publicação da escada avisa, como o `ValueNotifier` de antes.
      expect(
        const PracticeState().copyWith(repeat: _escada()),
        isNot(equals(const PracticeState().copyWith(repeat: _escada()))),
      );
    });
  });
}

void _campo() {
  group('PracticeField', () {
    test('state lê o campo do estado atual da fonte', () {
      final fonte = _Fonte(const PracticeState(correctCount: 2));
      final campo = PracticeField<int>(fonte, (s) => s.correctCount);

      expect(campo.state, 2);
      fonte.mudar(const PracticeState(correctCount: 3));
      expect(campo.state, 3);
      unawaited(fonte.close());
    });

    test('stream repete só quando o campo muda', () async {
      final fonte = _Fonte(const PracticeState());
      final campo = PracticeField<int>(fonte, (s) => s.correctCount);
      final vistos = <int>[];
      final sub = campo.stream.listen(vistos.add);

      fonte.mudar(const PracticeState(correctCount: 1, wrongCount: 4));
      fonte.mudar(const PracticeState(correctCount: 1, wrongCount: 5));
      fonte.mudar(const PracticeState(correctCount: 2, wrongCount: 5));
      await pumpEventQueue();

      expect(vistos, [1, 2]);
      await sub.cancel();
      await fonte.close();
    });
  });
}

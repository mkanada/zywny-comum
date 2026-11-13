// LP25 — A escada de repetição (puro, sem Flutter): os degraus de cada etapa e a
// ordem de subir e de voltar.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/repeat_ladder.dart';

const _speeds = [0.5, 0.75, 0.9, 1.0];

void main() {
  group('os degraus de uma etapa', () {
    test('etapa só notas: só o degrau de notas', () {
      final ladder = RepeatLadder.of(top: null, speeds: _speeds);
      expect(ladder.rungs, [const RepeatRung.wait()]);
    });

    test('etapa de 50%: só notas e 50%', () {
      final ladder = RepeatLadder.of(top: 0.5, speeds: _speeds);
      expect(ladder.rungs, [
        const RepeatRung.wait(),
        const RepeatRung.tempo(0.5),
      ]);
    });

    test('etapa de 75%: só notas, 50% e 75% (sem 90% nem 100%)', () {
      final ladder = RepeatLadder.of(top: 0.75, speeds: _speeds);
      expect(ladder.rungs, [
        const RepeatRung.wait(),
        const RepeatRung.tempo(0.5),
        const RepeatRung.tempo(0.75),
      ]);
    });

    test('etapa de 100%: todos os degraus, até o andamento da etapa', () {
      final ladder = RepeatLadder.of(top: 1.0, speeds: _speeds);
      expect(ladder.rungs, [
        const RepeatRung.wait(),
        const RepeatRung.tempo(0.5),
        const RepeatRung.tempo(0.75),
        const RepeatRung.tempo(0.9),
        const RepeatRung.tempo(1.0),
      ]);
    });

    test('a ordem e as repetições dos andamentos não importam', () {
      final ladder = RepeatLadder.of(
        top: 0.9,
        speeds: [1.0, 0.75, 0.5, 0.75, 0.9],
      );
      expect(ladder.rungs, [
        const RepeatRung.wait(),
        const RepeatRung.tempo(0.5),
        const RepeatRung.tempo(0.75),
        const RepeatRung.tempo(0.9),
      ]);
    });

    test('o andamento da etapa é positivo', () {
      expect(
        () => RepeatLadder.of(top: 0, speeds: _speeds),
        throwsArgumentError,
      );
      expect(() => RepeatRung.tempo(0), throwsA(isA<AssertionError>()));
    });

    test('a escada não pode ser vazia', () {
      expect(() => RepeatLadder([]), throwsArgumentError);
    });
  });

  group('subir e voltar', () {
    test('errar no primeiro degrau: aviso e continua no primeiro', () {
      final ladder = RepeatLadder.of(top: 0.75, speeds: _speeds);
      final outcome = ladder.missed();
      expect(outcome.notice, RepeatNotice.missed);
      expect(outcome.next, const RepeatRung.wait());
      expect(outcome.countIn, isFalse);
      expect(ladder.index, 0);
      expect(outcome.finished, isFalse);
    });

    test('acertar no degrau de baixo sobe com aviso e contagem', () {
      final ladder = RepeatLadder.of(top: 0.75, speeds: _speeds);
      final outcome = ladder.passed();
      expect(outcome.notice, RepeatNotice.passed);
      expect(outcome.next, const RepeatRung.tempo(0.5));
      expect(outcome.countIn, isTrue);
      expect(ladder.current, const RepeatRung.tempo(0.5));
    });

    test('acertar no degrau da etapa termina a escada, sem aviso', () {
      final ladder = RepeatLadder.of(top: 0.75, speeds: _speeds);
      ladder.passed();
      ladder.passed();
      expect(ladder.current, const RepeatRung.tempo(0.75));
      final outcome = ladder.passed();
      expect(outcome.finished, isTrue);
      expect(outcome.notice, RepeatNotice.none);
      expect(outcome.next, isNull);
      expect(outcome.countIn, isFalse);
    });

    test('a escada só notas acaba no primeiro acerto', () {
      final ladder = RepeatLadder.of(top: null, speeds: _speeds);
      final outcome = ladder.passed();
      expect(outcome.finished, isTrue);
      expect(outcome.notice, RepeatNotice.none);
    });

    test('errar num degrau de cima volta ao primeiro, não ao de baixo', () {
      final ladder = RepeatLadder.of(top: 1.0, speeds: _speeds);
      ladder.passed(); // 50%
      ladder.passed(); // 75%
      expect(ladder.index, 2);
      final outcome = ladder.missed();
      expect(outcome.notice, RepeatNotice.missed);
      expect(outcome.next, const RepeatRung.wait());
      expect(ladder.index, 0);
      // De novo: sobe outra vez, do começo.
      expect(ladder.passed().next, const RepeatRung.tempo(0.5));
    });

    test('errar no degrau de 90% volta a só notas, e depois sobe até 100%', () {
      final ladder = RepeatLadder.of(top: 1.0, speeds: _speeds);
      for (var i = 0; i < 3; i++) {
        ladder.passed();
      }
      expect(ladder.current, const RepeatRung.tempo(0.9));
      ladder.missed();
      final walked = <RepeatRung>[ladder.current];
      RepeatOutcome outcome;
      do {
        outcome = ladder.passed();
        if (outcome.next != null) walked.add(outcome.next!);
      } while (!outcome.finished);
      expect(walked, [
        const RepeatRung.wait(),
        const RepeatRung.tempo(0.5),
        const RepeatRung.tempo(0.75),
        const RepeatRung.tempo(0.9),
        const RepeatRung.tempo(1.0),
      ]);
    });
  });

  test(
    'o degrau é igual pelo andamento; só notas é diferente de qualquer um',
    () {
      expect(const RepeatRung.tempo(0.5), const RepeatRung.tempo(0.5));
      expect(const RepeatRung.wait(), const RepeatRung.wait());
      expect(const RepeatRung.wait(), isNot(const RepeatRung.tempo(0.5)));
      expect(const RepeatRung.wait().isWait, isTrue);
      expect(const RepeatRung.tempo(0.5).isWait, isFalse);
    },
  );
}

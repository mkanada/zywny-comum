// A conferência do TRANSPOSE por dentro (Q06): o Cubit lê a tecla, faz o teste
// de ouvido e o da entrada, guarda o que descobre e para a escuta no close.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/transpose_check.dart';
import 'package:zywny_comum/settings/app_settings.dart';
import 'package:zywny_music/transposition.dart';

import '../support/practice_fakes.dart';

void main() {
  // Hino em Mi♭ → Dó: k = −3; o Dó central (60) soa Mi♭ (63).
  final minorThird = Transposition.parse('-m3')!;

  group('TransposeCheckCubit', () {
    late FakeMidiInput input;
    late List<int> ownSounds;
    late List<int> keyboardSounds;

    setUp(() {
      input = FakeMidiInput();
      ownSounds = [];
      keyboardSounds = [];
    });

    tearDown(() => input.dispose());

    TransposeCheckCubit criar({
      Duration keyTimeout = const Duration(seconds: 30),
      bool ownSound = true,
      bool keyboardOutput = false,
      KeyboardTransposeBehavior previous = KeyboardTransposeBehavior.unknown,
    }) => TransposeCheckCubit(
      transposition: minorThird,
      input: input,
      previous: previous,
      playOwnSound: (pitch) async {
        ownSounds.add(pitch);
        return ownSound;
      },
      playOnKeyboard: keyboardOutput
          ? (pitch) async => keyboardSounds.add(pitch)
          : null,
      keyTimeout: keyTimeout,
      inputGap: Duration.zero,
    );

    test('começa na instrução, sem nada descoberto', () {
      final cubit = criar();
      addTearDown(cubit.close);

      expect(cubit.state, const TransposeCheckState());
    });

    test('a tecla soada (63): o teclado transpõe a saída e acaba', () async {
      final cubit = criar();
      addTearDown(cubit.close);

      cubit.ouvirTecla();
      expect(cubit.state.step, TransposeStep.listening);
      input.press(63);
      await pumpEventQueue();

      expect(cubit.state.step, TransposeStep.done);
      expect(cubit.resultado().shiftsOut, isTrue);
    });

    test(
      'a tecla 60 e o ouvido igual: o teclado não transpõe a saída',
      () async {
        final cubit = criar();
        addTearDown(cubit.close);

        cubit.ouvirTecla();
        input.press(60);
        await pumpEventQueue();
        expect(cubit.state.step, TransposeStep.ear);
        expect(ownSounds, [
          63,
        ], reason: 'o app toca o Mi♭ que o Dó deveria soar');

        cubit.soSomNoTeclado();
        expect(cubit.state.step, TransposeStep.done);
        expect(cubit.resultado().shiftsOut, isFalse);
      },
    );

    test(
      'a tecla 60 sem som no app: o passo pede a palavra da pessoa',
      () async {
        final cubit = criar(ownSound: false);
        addTearDown(cubit.close);

        cubit.ouvirTecla();
        input.press(60);
        await pumpEventQueue();
        expect(cubit.state.step, TransposeStep.earNoSound);

        cubit.soSomNoTeclado();
        expect(cubit.resultado().shiftsOut, isFalse);
      },
    );

    test('outro valor: diz em quanto o teclado está', () async {
      final cubit = criar();
      addTearDown(cubit.close);

      cubit.ouvirTecla();
      input.press(62);
      await pumpEventQueue();

      expect(cubit.state.step, TransposeStep.offset);
      expect(cubit.state.offset, 2);
      expect(
        cubit.state.out,
        isTrue,
        reason: 'só quem transpõe a saída manda deslocado',
      );
    });

    test('outra oitava do Dó: pede o Dó do meio e não guarda nada', () async {
      final cubit = criar();
      addTearDown(cubit.close);

      cubit.ouvirTecla();
      input.press(72);
      await pumpEventQueue();

      expect(cubit.state.step, TransposeStep.wrongOctave);
      expect(cubit.state.out, isNull);
      cubit.tentarDeNovo();
      expect(cubit.state.step, TransposeStep.instruction);
    });

    test('prazo sem tecla: avisa que não chegou nada', () async {
      final cubit = criar(keyTimeout: const Duration(milliseconds: 10));
      addTearDown(cubit.close);

      cubit.ouvirTecla();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.step, TransposeStep.noKey);
    });

    test('com a saída de teclado, a entrada: a 1ª nota soou igual', () async {
      final cubit = criar(keyboardOutput: true);
      addTearDown(cubit.close);

      cubit.ouvirTecla();
      input.press(63);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.step, TransposeStep.inputTest);
      expect(cubit.state.inputPlayed, 2);
      expect(keyboardSounds, [60, 63]);

      cubit.respostaEntrada(shiftsIn: true);
      expect(cubit.state.step, TransposeStep.done);
      expect(cubit.resultado().shiftsIn, isTrue);
    });

    test('sem resposta da entrada, o que já se sabia fica', () {
      final cubit = criar(
        previous: const KeyboardTransposeBehavior(shiftsIn: false),
      );
      addTearDown(cubit.close);

      expect(cubit.resultado().shiftsIn, isFalse);
    });

    test(
      'fechar para a escuta: a tecla que chega depois não mexe em nada',
      () async {
        final cubit = criar();

        cubit.ouvirTecla();
        await cubit.close();
        input.press(63);
        await pumpEventQueue();

        expect(cubit.state.step, TransposeStep.listening);
        expect(cubit.isClosed, isTrue);
      },
    );
  });
}

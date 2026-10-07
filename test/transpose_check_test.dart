// Q06 — Conferência do TRANSPOSE do teclado: a leitura da tecla, os três
// caminhos do Dó central, o teste de ouvido, o teste da entrada, o prazo e a
// decisão de abrir sozinha. Hino em Mi♭ → Dó: `-m3`, k = −3, teclado em +3,
// o Dó central (60) soa Mi♭ (63).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/practice/transpose_check.dart';
import 'package:zywny/music/transposition.dart';
import 'package:zywny/settings/app_settings.dart';

import 'support/practice_fakes.dart';

void main() {
  final minorThird = Transposition.parse('-m3')!;

  group('classifyCheckKey (k = −3: o Dó central soa 63)', () {
    CheckKeyReading read(int p, [int k = -3]) => classifyCheckKey(p, k);

    test('63: o teclado transpõe a saída e está certo', () {
      expect(read(63).kind, CheckKeyKind.shiftsOut);
    });

    test('60: ambíguo, só o ouvido separa', () {
      expect(read(60).kind, CheckKeyKind.ambiguous);
    });

    test('outro valor: o TRANSPOSE em que o teclado está', () {
      final r = read(62);
      expect(r.kind, CheckKeyKind.offset);
      expect(r.offset, 2);
      expect(read(57).offset, -3);
    });

    test('outra oitava do Dó é engano, não TRANSPOSE ±12', () {
      expect(read(72).kind, CheckKeyKind.wrongOctave);
      expect(read(48).kind, CheckKeyKind.wrongOctave);
    });

    test('vale para k positivo', () {
      expect(read(57, 3).kind, CheckKeyKind.shiftsOut);
      expect(read(60, 3).kind, CheckKeyKind.ambiguous);
    });
  });

  test('signedTranspose', () {
    expect(signedTranspose(3), '+3');
    expect(signedTranspose(-5), '−5');
    expect(signedTranspose(0), '0');
  });

  group('shouldAutoCheckTranspose', () {
    bool should({
      Transposition? transposition,
      String? deviceName = 'Yamaha',
      KeyboardTransposeBehavior behavior = KeyboardTransposeBehavior.unknown,
      bool appIsSound = false,
      bool alreadyAsked = false,
    }) => shouldAutoCheckTranspose(
      transposition: transposition,
      deviceName: deviceName,
      behavior: behavior,
      appIsSound: appIsSound,
      alreadyAsked: alreadyAsked,
    );

    test('transposta, teclado conectado e não conferido: abre', () {
      expect(should(transposition: minorThird), isTrue);
    });

    test('sem transposição ou sem teclado: não abre', () {
      expect(should(), isFalse);
      expect(should(transposition: minorThird, deviceName: null), isFalse);
    });

    test('teclado já conferido: não abre', () {
      expect(
        should(
          transposition: minorThird,
          behavior: const KeyboardTransposeBehavior(shiftsOut: false),
        ),
        isFalse,
      );
    });

    test('o som é só do app, ou a pessoa já fechou: não abre', () {
      expect(should(transposition: minorThird, appIsSound: true), isFalse);
      expect(should(transposition: minorThird, alreadyAsked: true), isFalse);
    });
  });

  group('a folha', () {
    late FakeMidiInput input;
    late List<int> ownSounds;
    late List<int> keyboardSounds;
    KeyboardTransposeBehavior? result;
    var closed = false;

    setUp(() {
      input = FakeMidiInput();
      ownSounds = [];
      keyboardSounds = [];
      result = null;
      closed = false;
    });

    Future<void> open(
      WidgetTester tester, {
      bool ownSound = true,
      bool keyboardOutput = false,
      KeyboardTransposeBehavior previous = KeyboardTransposeBehavior.unknown,
      Duration keyTimeout = const Duration(seconds: 30),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showTransposeCheck(
                  context,
                  transposition: minorThird,
                  deviceName: 'Yamaha',
                  input: input,
                  previous: previous,
                  keyTimeout: keyTimeout,
                  inputGap: const Duration(milliseconds: 100),
                  playOwnSound: (pitch) async {
                    ownSounds.add(pitch);
                    return ownSound;
                  },
                  playOnKeyboard: keyboardOutput
                      ? (pitch) async => keyboardSounds.add(pitch)
                      : null,
                );
                closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, int pitch) async {
      input.press(pitch);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
    }

    testWidgets('instrução: o TRANSPOSE a ajustar e o que vai soar', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.text('No seu teclado, ajuste o TRANSPOSE para +3.'),
        findsOneWidget,
      );
      expect(find.textContaining('a tecla Dó vai soar Mi♭'), findsOneWidget);
      expect(find.textContaining('manual do seu teclado'), findsOneWidget);
    });

    testWidgets('chegou 63: transpõe a saída; guarda out e não mexe no in', (
      tester,
    ) async {
      await open(
        tester,
        previous: const KeyboardTransposeBehavior(shiftsIn: true),
      );
      await tap(tester, 'Já ajustei');
      expect(find.text('Toque o Dó central.'), findsOneWidget);
      await press(tester, 63);
      expect(ownSounds, isEmpty, reason: 'sem ambiguidade, sem ouvido');
      expect(find.text('Pronto.'), findsOneWidget);
      await tap(tester, 'Concluir');
      expect(
        result,
        const KeyboardTransposeBehavior(shiftsOut: true, shiftsIn: true),
      );
    });

    testWidgets('chegou 60 e soou igual: não transpõe a saída', (tester) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 60);
      expect(ownSounds, [63], reason: 'o app toca a soada, Mi♭4');
      expect(find.text('Soou igual à sua tecla Dó?'), findsOneWidget);
      await tap(tester, 'Sim');
      await tap(tester, 'Concluir');
      expect(result, const KeyboardTransposeBehavior(shiftsOut: false));
    });

    testWidgets('chegou 60 e não soou igual: volta à instrução, sem guardar', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 60);
      await tap(tester, 'Não');
      expect(find.text('Confira o TRANSPOSE: precisa ser +3.'), findsOneWidget);
      await tap(tester, 'Tentar de novo');
      expect(
        find.text('No seu teclado, ajuste o TRANSPOSE para +3.'),
        findsOneWidget,
      );
      expect(closed, isFalse);
      expect(result, isNull);
    });

    testWidgets('sem som no app: vale a palavra da pessoa (não transpõe)', (
      tester,
    ) async {
      await open(tester, ownSound: false);
      await tap(tester, 'Já ajustei');
      await press(tester, 60);
      expect(find.textContaining('Não deu para tocar aqui'), findsOneWidget);
      await tap(tester, 'Já ajustei');
      await tap(tester, 'Concluir');
      expect(result, const KeyboardTransposeBehavior(shiftsOut: false));
    });

    testWidgets('chegou outro valor: diz em quanto está, guarda out ao '
        'acertar', (tester) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 62);
      expect(
        find.text('Seu teclado parece estar em +2. Ajuste para +3.'),
        findsOneWidget,
      );
      await tap(tester, 'Tentar de novo');
      await tap(tester, 'Já ajustei');
      await press(tester, 63);
      await tap(tester, 'Concluir');
      expect(result, const KeyboardTransposeBehavior(shiftsOut: true));
    });

    testWidgets('vale a última descoberta: de +2 para 60 com o ouvido igual', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 62);
      await tap(tester, 'Tentar de novo');
      await tap(tester, 'Já ajustei');
      await press(tester, 60);
      await tap(tester, 'Sim');
      await tap(tester, 'Concluir');
      // O que vale é a última descoberta: 60 e o ouvido igual = não transpõe.
      expect(result, const KeyboardTransposeBehavior(shiftsOut: false));
    });

    testWidgets('outra oitava: pede o Dó do meio e não guarda nada', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 72);
      expect(find.textContaining('Toque o Dó do meio'), findsOneWidget);
      await tap(tester, 'Tentar de novo');
      expect(find.text('Toque o Dó central.'), findsOneWidget);
    });

    testWidgets('só as notas ligadas contam (soltar a tecla não responde)', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      input.release(63);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Toque o Dó central.'), findsOneWidget);
    });

    testWidgets('prazo sem nota: avisa e deixa tentar de novo', (tester) async {
      await open(tester, keyTimeout: const Duration(seconds: 2));
      await tap(tester, 'Já ajustei');
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text('Não chegou nada do teclado. Ele está conectado?'),
        findsOneWidget,
      );
      await tap(tester, 'Tentar de novo');
      expect(
        find.text('No seu teclado, ajuste o TRANSPOSE para +3.'),
        findsOneWidget,
      );
      // Uma nota atrasada não vale: ninguém está escutando.
      await press(tester, 63);
      expect(find.text('Pronto.'), findsNothing);
    });

    testWidgets('entrada, a 1ª soou igual: o teclado transpõe a entrada', (
      tester,
    ) async {
      await open(tester, keyboardOutput: true);
      await tap(tester, 'Já ajustei');
      await press(tester, 63);
      // O app manda a escrita (Dó4) e depois a soada (Mi♭4), crus.
      await tester.pump(const Duration(milliseconds: 500));
      expect(keyboardSounds, [60, 63]);
      expect(
        find.text('Qual soou igual à sua tecla Dó: a 1ª ou a 2ª?'),
        findsOneWidget,
      );
      await tap(tester, 'A 1ª');
      await tap(tester, 'Concluir');
      expect(
        result,
        const KeyboardTransposeBehavior(shiftsOut: true, shiftsIn: true),
      );
    });

    testWidgets('entrada, a 2ª soou igual: o teclado não transpõe a entrada', (
      tester,
    ) async {
      await open(tester, keyboardOutput: true);
      await tap(tester, 'Já ajustei');
      await press(tester, 60);
      await tap(tester, 'Sim');
      await tester.pump(const Duration(milliseconds: 500));
      await tap(tester, 'A 2ª');
      await tap(tester, 'Concluir');
      expect(
        result,
        const KeyboardTransposeBehavior(shiftsOut: false, shiftsIn: false),
      );
    });

    testWidgets('entrada: não dá para responder antes das duas notas', (
      tester,
    ) async {
      await open(tester, keyboardOutput: true);
      await tap(tester, 'Já ajustei');
      input.press(63);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.text('Vão soar duas notas no teclado, uma de cada vez…'),
        findsOneWidget,
      );
      final first = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'A 1ª'),
      );
      expect(first.onPressed, isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('celular deitado (640×360): cabe, rola e não estoura', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await open(tester, keyboardOutput: true);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Já ajustei');
      expect(tester.takeException(), isNull);
      expect(find.text('Toque o Dó central.'), findsOneWidget);
    });

    testWidgets('cancelar no meio não devolve nada', (tester) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await press(tester, 63);
      await tap(tester, 'Descartar');
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('fechar não deixa a escuta aberta', (tester) async {
      await open(tester);
      await tap(tester, 'Já ajustei');
      await tap(tester, 'Cancelar');
      expect(closed, isTrue);
      // Uma nota depois de fechar não derruba nada.
      input.press(63);
      await tester.pump(const Duration(milliseconds: 10));
      expect(result, isNull);
    });
  });

  group('guardado pelo nome do teclado', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('depois da conferência o teclado conta como conferido', () async {
      final settings = AppSettings(prefs: SharedPreferencesAsync());
      expect(settings.keyboardTransposeOf('Yamaha').isChecked, isFalse);
      settings.setKeyboardTranspose(
        'Yamaha',
        const KeyboardTransposeBehavior(shiftsOut: false),
      );
      expect(settings.keyboardTransposeOf('Yamaha').isChecked, isTrue);
      expect(settings.keyboardTransposeOf('Casio').isChecked, isFalse);
      // E a conferência não reabre sozinha para quem já foi conferido.
      expect(
        shouldAutoCheckTranspose(
          transposition: Transposition.parse('-m3'),
          deviceName: 'Yamaha',
          behavior: settings.keyboardTransposeOf('Yamaha'),
          appIsSound: false,
          alreadyAsked: false,
        ),
        isFalse,
      );
    });
  });
}

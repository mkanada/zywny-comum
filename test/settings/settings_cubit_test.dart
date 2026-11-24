// As configurações gerais no Cubit (BL08, antes AppSettings): o estado com
// os padrões, a carga do armazenamento, os setters que gravam e emitem, e o
// diagSnapshot do log. O que muda chega a `stream` numa microtask; `state` é
// síncrono (é o que o motor lê).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/settings/settings_cubit.dart';
import 'package:zywny_comum/trail/trail_stage.dart' show TrailPhase;

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('SettingsState', () {
    test('copyWith troca só o campo pedido', () {
      final estado = SettingsState();
      final mudado = estado.copyWith(soundOn: false);

      expect(mudado.soundOn, isFalse);
      expect(mudado.output, estado.output);
      expect(estado.copyWith(), estado);
    });

    test('é igual pelo valor (Equatable), inclusive os conjuntos', () {
      expect(
        SettingsState(trailSpeeds: {0.5, 1.0}),
        equals(SettingsState(trailSpeeds: {1.0, 0.5})),
      );
      expect(SettingsState(soundOn: false), isNot(equals(SettingsState())));
    });

    test('trailPlanPhases segue a ordem e tira as etapas desmarcadas', () {
      final ordem = [TrailPhase.junto, TrailPhase.notasD, TrailPhase.notasE];
      final estado = SettingsState(
        trailPhaseOrder: ordem,
        trailPhases: {TrailPhase.notasD, TrailPhase.junto},
      );

      expect(estado.trailPlanPhases, [TrailPhase.junto, TrailPhase.notasD]);
    });

    test('um teclado não conferido vale unknown', () {
      expect(
        SettingsState().keyboardTransposeOf('Yamaha'),
        KeyboardTransposeBehavior.unknown,
      );
    });

    test('diagSnapshot traz as chaves do log e as cores em hexadecimal', () {
      final snapshot = SettingsState(
        studentPartColor: const Color(0xFF6A1B9A),
        repeatNoticeSeconds: 4,
      ).diagSnapshot();

      expect(snapshot['corAluno'], '#ff6a1b9a');
      expect(snapshot['corDestaque'], '#ff2e7d32');
      expect(snapshot['avisoDaVoltaS'], 4);
      expect(snapshot['saida'], SoundOutput.appSynth.name);
      expect(snapshot['cifra'], 'brazilian');
      expect(snapshot.keys, hasLength(19));
    });
  });

  group('SettingsCubit', () {
    blocTest<SettingsCubit, SettingsState>(
      'load sem nada gravado põe os padrões',
      build: () => SettingsCubit(),
      act: (cubit) => cubit.load(),
      expect: () => [SettingsState(loaded: true)],
    );

    blocTest<SettingsCubit, SettingsState>(
      'load lê os valores gravados, e o que passa do limite é cortado',
      setUp: () {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'sound_output': 'midiKeyboard',
              'sound_on': false,
              'ui_student_part_color': 0xFFAA0000,
              'repeat_notice_seconds': 9.0,
            });
      },
      build: () => SettingsCubit(),
      act: (cubit) => cubit.load(),
      expect: () => [
        SettingsState(
          loaded: true,
          output: SoundOutput.midiKeyboard,
          soundOn: false,
          studentPartColor: const Color(0xFFAA0000),
          repeatNoticeSeconds: kMaxRepeatNoticeSeconds,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'setStudentPartColor emite a cor e grava a cor',
      build: () => SettingsCubit(),
      act: (cubit) => cubit.setStudentPartColor(const Color(0xFF123456)),
      expect: () => [
        predicate<SettingsState>(
          (s) => s.studentPartColor == const Color(0xFF123456),
        ),
      ],
      verify: (_) async {
        await Future<void>.delayed(Duration.zero);
        expect(
          await SharedPreferencesAsync().getInt('ui_student_part_color'),
          0xFF123456,
        );
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'setRepeatNoticeSeconds corta em 6 s e grava o valor cortado',
      build: () => SettingsCubit(),
      act: (cubit) => cubit.setRepeatNoticeSeconds(99),
      expect: () => [
        predicate<SettingsState>(
          (s) => s.repeatNoticeSeconds == kMaxRepeatNoticeSeconds,
        ),
      ],
      verify: (_) async {
        await Future<void>.delayed(Duration.zero);
        expect(
          await SharedPreferencesAsync().getDouble('repeat_notice_seconds'),
          kMaxRepeatNoticeSeconds,
        );
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'setOutput grava o nome da saída',
      build: () => SettingsCubit(),
      act: (cubit) => cubit.setOutput(SoundOutput.midiKeyboard),
      expect: () => [
        predicate<SettingsState>((s) => s.output == SoundOutput.midiKeyboard),
      ],
      verify: (_) async {
        await Future<void>.delayed(Duration.zero);
        expect(
          await SharedPreferencesAsync().getString('sound_output'),
          'midiKeyboard',
        );
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'setRhythmToleranceMs corta entre 30 e 200 ms',
      build: () => SettingsCubit(),
      act: (cubit) => cubit.setRhythmToleranceMs(500),
      expect: () => [
        predicate<SettingsState>(
          (s) => s.rhythmToleranceMs == kMaxRhythmToleranceMs,
        ),
      ],
      verify: (_) async {
        await Future<void>.delayed(Duration.zero);
        expect(
          await SharedPreferencesAsync().getDouble('rhythm_tolerance_ms'),
          kMaxRhythmToleranceMs,
        );
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'setSoundOn grava o booleano; o mesmo valor não emite nada',
      build: () => SettingsCubit(),
      act: (cubit) {
        cubit
          ..setSoundOn(false)
          ..setSoundOn(false);
      },
      expect: () => [predicate<SettingsState>((s) => s.soundOn == false)],
      verify: (_) async {
        await Future<void>.delayed(Duration.zero);
        expect(await SharedPreferencesAsync().getBool('sound_on'), isFalse);
      },
    );

    test('o state muda na hora, antes do aviso do stream', () async {
      final cubit = SettingsCubit();
      addTearDown(cubit.close);
      final avisos = <SettingsState>[];
      final sub = cubit.stream.listen(avisos.add);
      addTearDown(sub.cancel);

      cubit.setSoundOn(false);
      expect(cubit.state.soundOn, isFalse);
      expect(avisos, isEmpty, reason: 'o stream entrega numa microtask');

      await Future<void>.delayed(Duration.zero);
      expect(avisos, [cubit.state]);
    });

    test('load depois do close não emite nem lança', () async {
      final cubit = SettingsCubit();
      final carga = cubit.load();
      await cubit.close();

      await expectLater(carga, completes);
      expect(cubit.isClosed, isTrue);
      expect(cubit.state.loaded, isFalse);
    });

    test('lastPieceTransposed não é estado: não emite', () async {
      final cubit = SettingsCubit();
      addTearDown(cubit.close);
      final avisos = <SettingsState>[];
      final sub = cubit.stream.listen(avisos.add);
      addTearDown(sub.cancel);

      cubit.lastPieceTransposed = true;
      await Future<void>.delayed(Duration.zero);

      expect(cubit.lastPieceTransposed, isTrue);
      expect(avisos, isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_audio/soundfont_store.dart';
import 'package:zywny_comum/app/general_settings_cubit.dart';
import 'package:zywny_midi/midi_device_manager.dart';

/// O `.sf2` do usuário em memória: lê se há um, grava e apaga.
class _FakeSoundFonts extends SoundFontStore {
  _FakeSoundFonts({this.custom = false, this.falhaAoGravar});

  bool custom;

  /// Se não for `null`, gravar lança esta exceção.
  final Object? falhaAoGravar;
  int gravacoes = 0;
  int limpezas = 0;

  @override
  Future<bool> hasCustom() async => custom;

  @override
  Future<void> saveCustom(Uint8List bytes) async {
    if (falhaAoGravar != null) throw falhaAoGravar!;
    gravacoes++;
    custom = true;
  }

  @override
  Future<void> clearCustom() async {
    limpezas++;
    custom = false;
  }
}

class _SemTeclados implements MidiCommand {
  @override
  Future<List<MidiDevice>?> get devices async => const [];

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _bytes = Uint8List.fromList([1, 2, 3]);

void main() {
  group('GeneralSettingsState', () {
    test('copyWith troca só o campo pedido', () {
      const estado = GeneralSettingsState(customSoundFont: true, errors: 2);

      expect(estado.copyWith(), estado);
      expect(estado.copyWith(errors: 3).errors, 3);
      expect(estado.copyWith(errors: 3).customSoundFont, isTrue);
    });
  });

  group('GeneralSettingsCubit (timbre do piano)', () {
    blocTest<GeneralSettingsCubit, GeneralSettingsState>(
      'atualizar lê se há timbre próprio',
      build: () => GeneralSettingsCubit(
        soundFonts: _FakeSoundFonts(custom: true),
        pickSoundFont: () async => null,
      ),
      act: (cubit) => cubit.atualizar(),
      expect: () => [const GeneralSettingsState(customSoundFont: true)],
    );

    final cancelado = _FakeSoundFonts();
    blocTest<GeneralSettingsCubit, GeneralSettingsState>(
      'cancelar o seletor não grava nem relê',
      build: () => GeneralSettingsCubit(
        soundFonts: cancelado,
        pickSoundFont: () async => null,
      ),
      act: (cubit) => cubit.escolherTimbre(),
      expect: () => <GeneralSettingsState>[],
      verify: (_) => expect(cancelado.gravacoes, 0),
    );

    final escolhido = _FakeSoundFonts();
    blocTest<GeneralSettingsCubit, GeneralSettingsState>(
      'escolher um .sf2 o grava e passa a ser o próprio',
      build: () => GeneralSettingsCubit(
        soundFonts: escolhido,
        pickSoundFont: () async => _bytes,
      ),
      act: (cubit) => cubit.escolherTimbre(),
      expect: () => [const GeneralSettingsState(customSoundFont: true)],
      verify: (_) => expect(escolhido.gravacoes, 1),
    );

    test(
      'uma falha ao gravar vira mensagem e sobe o contador de falhas',
      () async {
        final cubit = GeneralSettingsCubit(
          soundFonts: _FakeSoundFonts(falhaAoGravar: Exception('disco cheio')),
          pickSoundFont: () async => _bytes,
        );
        addTearDown(cubit.close);

        await cubit.escolherTimbre();
        expect(cubit.state.errors, 1);
        expect(
          cubit.state.soundFontError,
          'não consegui usar esse soundfont (Exception: disco cheio)',
        );
        expect(cubit.state.customSoundFont, isFalse);

        // A mesma falha de novo sobe o contador: o SnackBar aparece outra vez.
        await cubit.escolherTimbre();
        expect(cubit.state.errors, 2);
      },
    );

    final voltando = _FakeSoundFonts(custom: true);
    blocTest<GeneralSettingsCubit, GeneralSettingsState>(
      'voltar ao padrão apaga o próprio e relê',
      build: () => GeneralSettingsCubit(
        soundFonts: voltando,
        pickSoundFont: () async => null,
      ),
      seed: () => const GeneralSettingsState(customSoundFont: true),
      act: (cubit) => cubit.voltarAoPadrao(),
      expect: () => [const GeneralSettingsState()],
      verify: (_) => expect(voltando.limpezas, 1),
    );

    test(
      'se a tela fechar antes do seletor voltar, não emite nem lança',
      () async {
        final escolha = Completer<Uint8List?>();
        final cubit = GeneralSettingsCubit(
          soundFonts: _FakeSoundFonts(falhaAoGravar: Exception('tarde')),
          pickSoundFont: () => escolha.future,
        );

        final carga = cubit.escolherTimbre();
        await cubit.close();
        escolha.complete(_bytes);

        await expectLater(carga, completes);
        expect(cubit.isClosed, isTrue);
        expect(
          cubit.state.errors,
          0,
          reason: 'o estado não mudou depois do close',
        );
      },
    );
  });

  group('LatencyTileCubit', () {
    late MidiDeviceManager manager;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      manager = MidiDeviceManager(
        midi: _SemTeclados(),
        prefs: SharedPreferencesAsync(),
      );
    });

    tearDown(() => manager.close());

    test('sem medida guardada, a linha fica sem valor', () async {
      final cubit = LatencyTileCubit(devices: manager, deviceId: 'kb-1');
      addTearDown(cubit.close);

      await cubit.carregar();
      expect(cubit.state.last, isNull);
    });

    test('carregar lê a medida guardada do teclado', () async {
      await manager.setSoundLatency('kb-1', 41.6, corrected: true);
      final cubit = LatencyTileCubit(devices: manager, deviceId: 'kb-1');
      addTearDown(cubit.close);

      await cubit.carregar();
      expect(cubit.state.last, isNotNull);
      expect(cubit.state.last, await manager.soundLatency('kb-1'));
      expect(cubit.state.last!.corrected, isTrue);
    });

    test('se a linha fechar antes da leitura, não emite nem lança', () async {
      await manager.setSoundLatency('kb-1', 41.6, corrected: true);
      final cubit = LatencyTileCubit(devices: manager, deviceId: 'kb-1');

      final carga = cubit.carregar();
      await cubit.close();

      await expectLater(carga, completes);
      expect(cubit.state.last, isNull);
    });
  });
}

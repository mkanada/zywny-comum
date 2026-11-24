// O estado das configurações gerais que não é valor do AppSettings (esse
// continua no próprio store): se o timbre do piano é o próprio, a falha da
// última troca, e a última medida de latência de cada teclado.

import 'dart:typed_data';

import 'package:zywny_audio/soundfont_store.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_midi/midi_device_manager.dart';

/// A tela de configurações gerais: o timbre do piano e a falha da última troca.
class GeneralSettingsState extends Equatable {
  const GeneralSettingsState({
    this.customSoundFont = false,
    this.soundFontError,
    this.errors = 0,
  });

  /// O usuário escolheu um `.sf2` próprio (senão vale o TimGM6mb embutido).
  final bool customSoundFont;

  /// A mensagem da última troca de timbre que falhou (vai num SnackBar).
  final String? soundFontError;

  /// Sobe a cada falha, para o SnackBar aparecer mesmo quando a mensagem é a
  /// mesma da vez anterior.
  final int errors;

  GeneralSettingsState copyWith({
    bool? customSoundFont,
    String? soundFontError,
    int? errors,
  }) => GeneralSettingsState(
    customSoundFont: customSoundFont ?? this.customSoundFont,
    soundFontError: soundFontError ?? this.soundFontError,
    errors: errors ?? this.errors,
  );

  @override
  List<Object?> get props => [customSoundFont, soundFontError, errors];
}

/// O timbre do piano nas configurações gerais: trocar pelo `.sf2` escolhido,
/// ou voltar ao padrão. A gravação continua no [SoundFontStore].
class GeneralSettingsCubit extends Cubit<GeneralSettingsState> {
  GeneralSettingsCubit({required this.soundFonts, required this.pickSoundFont})
    : super(const GeneralSettingsState());

  final SoundFontStore soundFonts;

  /// Abre o seletor de `.sf2` e devolve os bytes, ou `null` se o usuário
  /// cancelou; os testes trocam por um falso.
  final Future<Uint8List?> Function() pickSoundFont;

  /// Lê se há um timbre próprio guardado (ao abrir a tela).
  Future<void> atualizar() async {
    final custom = await soundFonts.hasCustom();
    if (isClosed) return;
    emit(state.copyWith(customSoundFont: custom));
  }

  /// Escolhe um `.sf2` e o guarda. Cancelar não muda nada; uma falha vira
  /// [GeneralSettingsState.soundFontError].
  Future<void> escolherTimbre() async {
    try {
      final bytes = await pickSoundFont();
      if (bytes == null) return;
      await soundFonts.saveCustom(bytes);
    } on Object catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          soundFontError: 'não consegui usar esse soundfont ($e)',
          errors: state.errors + 1,
        ),
      );
    }
    await atualizar();
  }

  /// Volta ao timbre padrão (o `.sf2` embutido).
  Future<void> voltarAoPadrao() async {
    await soundFonts.clearCustom();
    await atualizar();
  }
}

/// A linha "Latência do som": a última medida guardada de um teclado.
class LatencyTileState extends Equatable {
  const LatencyTileState({this.last});

  /// Os ms da última medida e se ela já descontou o microfone; `null` enquanto
  /// não há medida (ou ela ainda não foi lida).
  final ({double ms, bool corrected})? last;

  @override
  List<Object?> get props => [last];
}

/// Lê a última medida de latência do teclado [deviceId] (a linha de
/// configurações mostra). Quem mede de novo chama [carregar] depois.
class LatencyTileCubit extends Cubit<LatencyTileState> {
  LatencyTileCubit({required this.devices, required this.deviceId})
    : super(const LatencyTileState());

  final MidiDeviceManager devices;
  final String deviceId;

  Future<void> carregar() async {
    final last = await devices.soundLatency(deviceId);
    if (isClosed) return;
    emit(LatencyTileState(last: last));
  }
}

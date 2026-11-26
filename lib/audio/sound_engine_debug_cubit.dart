// O painel de depuração do motor de áudio (K02/K03) em BLoC. Fala com o
// `NativeSoundEngine` (dart:ffi), então só o painel nativo o importa; na Web
// o painel é o stub vazio. O motor é um recurso deste Cubit: o `close()` o
// descarta, e o tique das estatísticas para junto.

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:zywny_audio/native_sound_engine.dart';
import 'package:zywny_audio/sound_engine.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

/// Dó maior, C4-C5, a 120 bpm — a mesma escala de teste de K01/K02.
const List<int> _kScaleKeys = [60, 62, 64, 65, 67, 69, 71, 72];
const double _kBeatSeconds = 0.5;

/// O que o painel mostra: a frase de estado, se o toque está em andamento e um
/// contador que sobe a cada tique das estatísticas.
class SoundEngineDebugState extends Equatable {
  const SoundEngineDebugState({
    this.status = 'motor não iniciado',
    this.busy = false,
    this.serial = 0,
  });

  /// "tocando a escala de teste…", "erro: …" e o resto da frase de estado.
  final String status;

  /// O motor está sendo aberto ou carregado: o botão fica desligado.
  final bool busy;

  /// Sobe a cada tique (500 ms). O motor muda os contadores (underruns,
  /// descartados) sem avisar, e a tela os relê a cada tique: a renotificação
  /// de mesmo valor é de propósito.
  final int serial;

  SoundEngineDebugState copyWith({String? status, bool? busy, int? serial}) =>
      SoundEngineDebugState(
        status: status ?? this.status,
        busy: busy ?? this.busy,
        serial: serial ?? this.serial,
      );

  @override
  List<Object?> get props => [status, busy, serial];
}

/// Abre o `.sf2` escolhido pelo aluno (o seletor de arquivos do sistema).
Future<XFile?> _abrirSoundfont() {
  const typeGroup = XTypeGroup(label: 'soundfont', extensions: ['sf2']);
  return openFile(acceptedTypeGroups: [typeGroup]);
}

/// O painel de depuração: abre o motor, carrega um `.sf2` e toca a escala de
/// teste. [criarMotor] e [escolherSoundfont] são trocados pelos testes.
class SoundEngineDebugCubit extends Cubit<SoundEngineDebugState> {
  SoundEngineDebugCubit({
    NativeSoundEngine Function()? criarMotor,
    Future<XFile?> Function()? escolherSoundfont,
  }) : _criarMotor = criarMotor ?? NativeSoundEngine.new,
       _escolherSoundfont = escolherSoundfont ?? _abrirSoundfont,
       super(const SoundEngineDebugState());

  final NativeSoundEngine Function() _criarMotor;
  final Future<XFile?> Function() _escolherSoundfont;

  NativeSoundEngine? _motor;
  Timer? _estatisticas;
  static const _tique = Duration(milliseconds: 500);

  void _amostrar(Timer _) => _emitir(state.copyWith(serial: state.serial + 1));

  /// O motor aberto, para a tela ler as estatísticas; `null` antes do primeiro
  /// toque.
  NativeSoundEngine? get motor => _motor;

  /// Abre o motor (na primeira vez), pede o `.sf2`, carrega e toca a escala.
  /// Fechado o Cubit no meio, nada mais é feito: cada `await` confere
  /// `isClosed` antes de seguir.
  Future<void> tocarEscalaDeTeste() async {
    if (state.busy) return;
    _emitir(state.copyWith(busy: true, status: 'abrindo motor de áudio…'));
    try {
      final motor = await _garantirMotor();
      if (motor == null) return;
      final arquivo = await _escolherSoundfont();
      if (isClosed) return;
      if (arquivo == null) {
        _emitir(
          state.copyWith(
            busy: false,
            status: 'cancelado (nenhum .sf2 escolhido)',
          ),
        );
        return;
      }
      _emitir(state.copyWith(status: 'carregando ${arquivo.name}…'));
      await motor.loadSoundFont(await arquivo.readAsBytes());
      if (isClosed) return;
      _agendarEscala(motor);
      _emitir(
        state.copyWith(busy: false, status: 'tocando a escala de teste…'),
      );
    } catch (e) {
      _emitir(state.copyWith(busy: false, status: 'erro: $e'));
    }
  }

  /// O motor já aberto, ou um novo, iniciado; o tique das estatísticas começa
  /// junto dele. `null` se o Cubit fechou enquanto o motor abria: aí o motor
  /// novo é descartado aqui, porque o `close()` não o tinha visto.
  Future<NativeSoundEngine?> _garantirMotor() async {
    final existente = _motor;
    if (existente != null) return existente;
    final motor = _criarMotor();
    await motor.start();
    if (isClosed) {
      unawaited(motor.dispose());
      return null;
    }
    _motor = motor;
    // As estatísticas do motor nativo são amostradas no ritmo dele (decisão 2).
    _estatisticas ??= Timer.periodic(_tique, _amostrar); // relógio: decisão 2
    return motor;
  }

  void _agendarEscala(SoundEngine motor) {
    final start = motor.earliestScheduleSeconds + 0.2;
    final events = <ScheduledMidi>[];
    for (var i = 0; i < _kScaleKeys.length; i++) {
      final key = _kScaleKeys[i];
      final on = start + i * _kBeatSeconds;
      final off = on + _kBeatSeconds * 0.9;
      events.add(ScheduledMidi(on, 0x90, key, 100));
      events.add(ScheduledMidi(off, 0x80, key, 0));
    }
    motor.schedule(events);
  }

  /// Emite só se o Cubit está aberto: a abertura ou o arquivo podem terminar
  /// depois de a tela fechar.
  void _emitir(SoundEngineDebugState novo) {
    if (!isClosed) emit(novo);
  }

  @override
  Future<void> close() {
    _estatisticas?.cancel();
    unawaited(_motor?.dispose());
    return super.close();
  }
}

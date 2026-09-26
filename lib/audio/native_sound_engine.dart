import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../native_paths.dart';
import 'sound_engine.dart';

/// Espelha `ZyEvent` do header C (`include/zywny_audio.h`, K02): `frame` +
/// 3 bytes MIDI + 1 de padding explícito.
final class _ZyEvent extends Struct {
  @Uint64()
  external int frame;
  @Uint8()
  external int status;
  @Uint8()
  external int d1;
  @Uint8()
  external int d2;
  @Uint8()
  external int pad;
}

// `size_t`/`uint64_t` mapeados para `Uint64`: os alvos deste projeto (Linux,
// Android arm64, Windows x64 — K01-K06) são todos de 64 bits.
typedef _EngineNewNative = Pointer<Void> Function(Int32);
typedef _EngineNewDart = Pointer<Void> Function(int);

typedef _LoadSf2Native = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint64);
typedef _LoadSf2Dart = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef _VoidFromPtrNative = Void Function(Pointer<Void>);
typedef _VoidFromPtrDart = void Function(Pointer<Void>);

typedef _Int32FromPtrNative = Int32 Function(Pointer<Void>);
typedef _Int32FromPtrDart = int Function(Pointer<Void>);

typedef _Uint64FromPtrNative = Uint64 Function(Pointer<Void>);
typedef _Uint64FromPtrDart = int Function(Pointer<Void>);

typedef _SendNative = Void Function(Pointer<Void>, Uint8, Uint8, Uint8);
typedef _SendDart = void Function(Pointer<Void>, int, int, int);

typedef _ScheduleNative =
    Void Function(Pointer<Void>, Pointer<_ZyEvent>, Uint64);
typedef _ScheduleDart = void Function(Pointer<Void>, Pointer<_ZyEvent>, int);

typedef _SetGainNative = Void Function(Pointer<Void>, Float);
typedef _SetGainDart = void Function(Pointer<Void>, double);

typedef _StatNative = Uint64 Function(Pointer<Void>, Int32);
typedef _StatDart = int Function(Pointer<Void>, int);

typedef _LastErrorNative = Pointer<pkg_ffi.Utf8> Function();
typedef _LastErrorDart = Pointer<pkg_ffi.Utf8> Function();

/// Bindings 1:1 às funções `zy_*` de `include/zywny_audio.h`, resolvidas
/// uma vez a partir da [DynamicLibrary] aberta.
class _ZyBindings {
  _ZyBindings(DynamicLibrary lib)
    : engineNew = lib.lookupFunction<_EngineNewNative, _EngineNewDart>(
        'zy_engine_new',
      ),
      engineLoadSf2 = lib.lookupFunction<_LoadSf2Native, _LoadSf2Dart>(
        'zy_engine_load_sf2',
      ),
      engineFree = lib.lookupFunction<_VoidFromPtrNative, _VoidFromPtrDart>(
        'zy_engine_free',
      ),
      sampleRate = lib.lookupFunction<_Int32FromPtrNative, _Int32FromPtrDart>(
        'zy_sample_rate',
      ),
      outputLatencyFrames =
          lib.lookupFunction<_Int32FromPtrNative, _Int32FromPtrDart>(
            'zy_output_latency_frames',
          ),
      nowFrame = lib.lookupFunction<_Uint64FromPtrNative, _Uint64FromPtrDart>(
        'zy_now_frame',
      ),
      renderFrame =
          lib.lookupFunction<_Uint64FromPtrNative, _Uint64FromPtrDart>(
            'zy_render_frame',
          ),
      send = lib.lookupFunction<_SendNative, _SendDart>('zy_send'),
      scheduleBatch = lib.lookupFunction<_ScheduleNative, _ScheduleDart>(
        'zy_schedule',
      ),
      clearScheduled =
          lib.lookupFunction<_VoidFromPtrNative, _VoidFromPtrDart>(
            'zy_clear_scheduled',
          ),
      allNotesOff = lib.lookupFunction<_VoidFromPtrNative, _VoidFromPtrDart>(
        'zy_all_notes_off',
      ),
      setGain = lib.lookupFunction<_SetGainNative, _SetGainDart>(
        'zy_set_gain',
      ),
      stat = lib.lookupFunction<_StatNative, _StatDart>('zy_stat'),
      lastError = lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'zy_last_error',
      );

  final _EngineNewDart engineNew;
  final _LoadSf2Dart engineLoadSf2;
  final _VoidFromPtrDart engineFree;
  final _Int32FromPtrDart sampleRate;
  final _Int32FromPtrDart outputLatencyFrames;
  final _Uint64FromPtrDart nowFrame;
  final _Uint64FromPtrDart renderFrame;
  final _SendDart send;
  final _ScheduleDart scheduleBatch;
  final _VoidFromPtrDart clearScheduled;
  final _VoidFromPtrDart allNotesOff;
  final _SetGainDart setGain;
  final _StatDart stat;
  final _LastErrorDart lastError;
}

/// `which` de [NativeSoundEngine.stat] — espelha `ZY_STAT_*` do header C.
const int zyStatUnderruns = 0;
const int zyStatDroppedEvents = 1;

/// [SoundEngine] sobre o motor nativo `zywny_audio` (K02), por `dart:ffi`.
/// Único ponto do app que sabe que esse motor existe — o resto fala só com
/// [SoundEngine].
class NativeSoundEngine implements SoundEngine {
  NativeSoundEngine({this.preferredBufferFrames = 256})
    : _bindings = _ZyBindings(DynamicLibrary.open(findAudioLibrary()));

  /// Buffer pequeno pedido ao dispositivo; o real pode divergir — ver
  /// [outputLatencySeconds].
  final int preferredBufferFrames;

  final _ZyBindings _bindings;
  Pointer<Void> _engine = nullptr;
  Pointer<_ZyEvent> _eventBuffer = nullptr;
  int _eventBufferCapacity = 0;
  int? _sampleRate;

  @override
  Future<void> start() async {
    final engine = _bindings.engineNew(preferredBufferFrames);
    if (engine == nullptr) {
      throw StateError('zy_engine_new falhou: ${_lastError()}');
    }
    _engine = engine;
    _sampleRate = _bindings.sampleRate(_engine);
  }

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {
    _checkStarted();
    final buf = pkg_ffi.malloc<Uint8>(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      final rc = _bindings.engineLoadSf2(_engine, buf, bytes.length);
      if (rc != 0) {
        throw StateError('zy_engine_load_sf2 falhou: ${_lastError()}');
      }
    } finally {
      pkg_ffi.malloc.free(buf);
    }
  }

  @override
  double get nowSeconds => _framesToSeconds(_bindings.nowFrame(_engine));

  @override
  double get earliestScheduleSeconds =>
      _framesToSeconds(_bindings.renderFrame(_engine));

  @override
  double get outputLatencySeconds =>
      _bindings.outputLatencyFrames(_engine) / _sampleRateOrThrow;

  /// Sample rate do dispositivo, em Hz — só para o painel de debug (não
  /// faz parte de [SoundEngine]).
  int get sampleRate => _sampleRateOrThrow;

  @override
  void send(List<int> midi) {
    _checkStarted();
    _bindings.send(_engine, midi[0], midi[1], midi[2]);
  }

  @override
  void schedule(List<ScheduledMidi> events) {
    _checkStarted();
    _ensureEventBufferCapacity(events.length);
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      final entry = (_eventBuffer + i).ref;
      entry.frame = _secondsToFrames(e.at);
      entry.status = e.status;
      entry.d1 = e.d1;
      entry.d2 = e.d2;
    }
    _bindings.scheduleBatch(_engine, _eventBuffer, events.length);
  }

  @override
  void clearScheduled() {
    _checkStarted();
    _bindings.clearScheduled(_engine);
  }

  @override
  void allNotesOff() {
    _checkStarted();
    _bindings.allNotesOff(_engine);
  }

  void setGain(double gain) {
    _checkStarted();
    _bindings.setGain(_engine, gain);
  }

  /// Estatística cumulativa (`zyStatUnderruns`/`zyStatDroppedEvents`) — só
  /// para o painel de debug. `0` se [start] ainda não foi chamado.
  int stat(int which) =>
      _engine == nullptr ? 0 : _bindings.stat(_engine, which);

  @override
  Future<void> dispose() async {
    if (_eventBuffer != nullptr) {
      pkg_ffi.malloc.free(_eventBuffer);
      _eventBuffer = nullptr;
      _eventBufferCapacity = 0;
    }
    if (_engine != nullptr) {
      _bindings.engineFree(_engine);
      _engine = nullptr;
    }
  }

  int _secondsToFrames(double seconds) =>
      (seconds * _sampleRateOrThrow).round();

  double _framesToSeconds(int frames) => frames / _sampleRateOrThrow;

  int get _sampleRateOrThrow =>
      _sampleRate ?? (throw StateError('start() não foi chamado'));

  void _checkStarted() {
    if (_engine == nullptr) {
      throw StateError('start() não foi chamado');
    }
  }

  void _ensureEventBufferCapacity(int n) {
    if (n <= _eventBufferCapacity) return;
    if (_eventBuffer != nullptr) {
      pkg_ffi.malloc.free(_eventBuffer);
    }
    _eventBuffer = pkg_ffi.malloc<_ZyEvent>(n);
    _eventBufferCapacity = n;
  }

  String _lastError() {
    final ptr = _bindings.lastError();
    return ptr == nullptr ? '(sem mensagem)' : ptr.toDartString();
  }
}

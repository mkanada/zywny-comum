import 'dart:js_interop';
import 'dart:typed_data';

import 'sound_engine.dart';

/// O módulo `web/audio/zywny_audio.js` (fonte em `web_src/`, gerado por
/// `tool/build_audio_web.sh`): SpessaSynth num AudioWorklet.
extension type _ZywnyAudio._(JSObject _) implements JSObject {
  external JSPromise<JSNumber> init();
  external JSPromise<JSAny?> loadSoundFont(JSUint8Array bytes);
  external void send(int status, int d1, int d2);
  external void schedule(JSFloat64Array times, JSUint8Array bytes);
  external void clear();
  external void allOff();
  external double now();
  external double earliest();
  external double latency();
  external double baseLatency();
  external double outputLatency();
  external double peak();
  external String state();
  external void dispose();
}

/// [SoundEngine] da Web (W04): o mesmo `.sf2` das outras plataformas, tocado
/// pelo SpessaSynth. O relógio é o do `AudioContext` — em segundos, como a
/// interface já espera, sem conversão nenhuma.
///
/// O módulo JS só é baixado (≈ 600 KB) quando o som é aberto pela primeira
/// vez, não na abertura do app.
class WebSoundEngine implements SoundEngine {
  _ZywnyAudio? _audio;

  _ZywnyAudio get _a => _audio ?? (throw StateError('start() não foi chamado'));

  @override
  Future<void> start() async {
    if (_audio != null) return;
    final module = await importModule('./audio/zywny_audio.js'.toJS).toDart;
    final audio = _ZywnyAudio._(module);
    await audio.init().toDart;
    _audio = audio;
  }

  @override
  Future<void> loadSoundFont(Uint8List bytes) async {
    await _a.loadSoundFont(bytes.toJS).toDart;
  }

  @override
  double get nowSeconds => _a.now();

  @override
  double get earliestScheduleSeconds => _a.earliest();

  @override
  double get outputLatencySeconds => _a.latency();

  /// `AudioContext.baseLatency`/`outputLatency` (s), para o registro de W04 e
  /// o painel de debug. `outputLatency` é 0 onde o navegador não informa.
  ({double base, double output}) get latencies =>
      (base: _a.baseLatency(), output: _a.outputLatency());

  /// Maior amplitude (0..1) saindo agora — para testar sem ouvir.
  double get peak => _a.peak();

  /// `running`, `suspended` (esperando um gesto do usuário) ou `closed`.
  String get contextState => _a.state();

  @override
  void send(List<int> midi) => _a.send(midi[0], midi[1], midi[2]);

  @override
  void schedule(List<ScheduledMidi> events) {
    if (events.isEmpty) return;
    final times = Float64List(events.length);
    final bytes = Uint8List(events.length * 3);
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      times[i] = e.at;
      bytes[3 * i] = e.status;
      bytes[3 * i + 1] = e.d1;
      bytes[3 * i + 2] = e.d2;
    }
    _a.schedule(times.toJS, bytes.toJS);
  }

  @override
  void clearScheduled() => _a.clear();

  @override
  void allNotesOff() => _a.allOff();

  @override
  Future<void> dispose() async {
    _audio?.dispose();
    _audio = null;
  }
}

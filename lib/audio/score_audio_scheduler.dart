// K04: converte a posição musical (ms, o relógio de [PerformanceTrack]) em
// eventos MIDI agendados no relógio do dispositivo (`SoundEngine.nowSeconds`)
// — ver docs/plano/K04-agendador-e-play-com-som.md.
//
// ÂNCORA: toda troca de posição (play, pause, seek, speed) recalcula
// `(deviceT0, musicalT0, speed)` do zero — a posição nunca é integrada tick a
// tick, então não acumula deriva.
//
// JANELA: [pump] agenda tudo que começa entre o que já foi coberto e
// `agora + lookahead`. Cada evento tem `onMs`/`offMs` já resolvidos pelo
// `PerformanceTrack` (ligadura fundida, ornamento expandido), então o par
// note-on/note-off é sempre agendado junto, mesmo que `offMs` caia bem além
// da janela — o motor aceita futuro distante (K02), então não há por que
// guardar um mapa de note-offs pendentes à parte.
import 'dart:async';

import '../music/performance_track.dart';
import 'sound_engine.dart';

/// Quanto um note-off antecipa `offMs`: a mesma tecla religada logo em
/// seguida (a próxima nota do evento seguinte) não pode ser cortada pelo
/// note-off da anterior.
const _kNoteOffLeadSeconds = 0.001;

/// Agendador puro (sem widgets) que liga [PerformanceTrack] a [SoundEngine]:
/// mantém a agenda do motor preenchida um pouco à frente do relógio do
/// dispositivo. Testável com um `FakeSoundEngine` que só registra
/// (`autoTick: false` evita o `Timer.periodic` de verdade — os testes
/// chamam [pump] direto).
class ScoreAudioScheduler {
  ScoreAudioScheduler({
    required this.engine,
    required this.track,
    this.lookahead = const Duration(milliseconds: 250),
    this.tickInterval = const Duration(milliseconds: 25),
    // Não dá para virar `this._autoTick`: o parâmetro é público, o campo é
    // privado.
    bool autoTick = true,
  }) : _autoTick = autoTick; // ignore: prefer_initializing_formals

  final SoundEngine engine;
  final PerformanceTrack track;

  /// Até quanto tempo (do dispositivo) à frente do relógio a agenda fica
  /// preenchida.
  final Duration lookahead;

  /// Intervalo do `Timer.periodic` que chama [pump] sozinho.
  final Duration tickInterval;

  final bool _autoTick;

  Timer? _timer;
  bool _running = false;

  double _deviceT0 = 0;
  double _musicalT0 = 0;
  double _speed = 1.0;

  /// Borda superior (exclusiva) da janela já coberta por [pump] — a próxima
  /// chamada só pede a [PerformanceTrack.startingIn] o que vem depois.
  double _scheduledUpToMs = 0;

  /// Freio do modo espera (T02): quando não-nulo, [positionMs] e o
  /// horizonte de [pump] não passam daqui — a posição "estaciona" no `onMs`
  /// do passo pendente em vez de correr livre, e nada é agendado além
  /// disso (nem os eventos da mão do app).
  double? _brakeMs;

  /// Filtro de pauta do modo espera (T02): quando não-nulo, só eventos
  /// dessas pautas entram em [pump] — é assim que "o app toca a outra mão"
  /// (a pauta do aluno nunca é agendada, ele toca fisicamente).
  Set<int>? _staves;

  double get speed => _speed;
  bool get isRunning => _running;

  /// Posição musical atual, em ms — parada (o valor da última âncora)
  /// enquanto não [isRunning], e capada em [_brakeMs] quando o freio do
  /// modo espera está armado.
  double get positionMs {
    if (!_running) return _musicalT0;
    final raw = _musicalAt(engine.nowSeconds);
    final brake = _brakeMs;
    return brake == null ? raw : (raw < brake ? raw : brake);
  }

  /// Arma (ou solta, com `null`) o freio do modo espera no `onMs` do passo
  /// pendente. Reancora a posição atual primeiro — ela pode estar havia um
  /// tempo estacionada no freio anterior enquanto o relógio do dispositivo
  /// seguia correndo por baixo — para que o novo trecho comece a fluir
  /// exatamente daqui. **Não** usa [_reanchor] puro: isso zeraria
  /// [_scheduledUpToMs] de volta para a posição atual, reagendando (em
  /// duplicata) eventos que o `pump` de olhar-à-frente já tinha mandado ao
  /// motor antes do freio prender — o aluno pode soltar o passo antes do
  /// próximo tick do `pump`, então esse adiantamento é real, não hipotético.
  void setBrake(double? onMs) {
    final held = positionMs;
    _musicalT0 = held;
    _deviceT0 = engine.nowSeconds;
    if (_scheduledUpToMs < held) _scheduledUpToMs = held;
    _brakeMs = onMs;
  }

  /// Restringe (ou libera, com `null`) [pump] às pautas em [staves] — a
  /// mão que o app toca no modo espera.
  void setStaves(Set<int>? staves) {
    _staves = staves;
  }

  double _musicalAt(double deviceSeconds) =>
      _musicalT0 + (deviceSeconds - _deviceT0) * 1000 * _speed;

  double _deviceAt(double musicalMs) =>
      _deviceT0 + (musicalMs - _musicalT0) / (1000 * _speed);

  void _reanchor(double musicalMs, {double? speed}) {
    _musicalT0 = musicalMs;
    _deviceT0 = engine.nowSeconds;
    if (speed != null) _speed = speed;
    _scheduledUpToMs = musicalMs;
  }

  void _armTimer() {
    if (_autoTick) _timer ??= Timer.periodic(tickInterval, (_) => pump());
  }

  /// Começa (ou retoma) a tocar a partir de [fromMs]. Manda o Program
  /// Change de cada canal (uma vez, aqui) e liga a agenda.
  void play(double fromMs, {double? speed}) {
    engine.allNotesOff();
    _reanchor(fromMs, speed: speed);
    _running = true;
    _sendProgramChanges();
    _armTimer();
    pump();
  }

  /// Pausa na posição atual: silencia tudo e desarma a agenda.
  void pause() {
    if (!_running) return;
    final ms = positionMs;
    _timer?.cancel();
    _timer = null;
    engine.allNotesOff();
    _running = false;
    _reanchor(ms);
  }

  /// Vai para [toMs] sem religar notas que já estivessem soando ali
  /// (comportamento comum de sequenciador). Silencia o que estava soando;
  /// se estava tocando, a agenda recomeça da nova posição.
  void seek(double toMs) {
    engine.allNotesOff();
    final wasRunning = _running;
    _reanchor(toMs);
    if (wasRunning) {
      _armTimer();
      pump();
    }
  }

  /// Troca a velocidade sem perder a posição corrente nem prender notas.
  void setSpeed(double newSpeed) {
    if (newSpeed == _speed) return;
    final ms = positionMs;
    final wasRunning = _running;
    if (wasRunning) engine.allNotesOff();
    _reanchor(ms, speed: newSpeed);
    if (wasRunning) {
      _armTimer();
      pump();
    }
  }

  /// Para e volta ao início.
  void stop() {
    _timer?.cancel();
    _timer = null;
    engine.allNotesOff();
    _running = false;
    _reanchor(0);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    engine.allNotesOff();
    _running = false;
  }

  void _sendProgramChanges() {
    final programs = <int, int>{};
    for (final e in track.events) {
      programs.putIfAbsent(e.channel, () => e.program);
    }
    if (programs.isEmpty) return;
    final at = engine.earliestScheduleSeconds;
    engine.schedule([
      for (final entry in programs.entries)
        ScheduledMidi(at, 0xC0 | entry.key, entry.value, 0),
    ]);
  }

  /// Preenche a agenda até `lookahead` à frente do relógio do motor. O
  /// `Timer` interno chama isto sozinho; os testes chamam direto para
  /// simular ticks sem depender de tempo real.
  void pump() {
    if (!_running) return;

    final rawHorizonMs = _musicalAt(
      engine.nowSeconds + lookahead.inMicroseconds / 1e6,
    );
    final brake = _brakeMs;
    final horizonMs = brake == null || rawHorizonMs < brake
        ? rawHorizonMs
        : brake;
    if (horizonMs <= _scheduledUpToMs) return;

    final earliest = engine.earliestScheduleSeconds;
    final midi = <ScheduledMidi>[];
    for (final e in track.startingIn(
      _scheduledUpToMs,
      horizonMs,
      staves: _staves,
    )) {
      // Atrasado (tick perdido, GC): nunca descarte o par — toque no mais
      // cedo possível.
      final onAt = _clamp(_deviceAt(e.onMs), earliest);
      final rawOffAt = _deviceAt(e.offMs) - _kNoteOffLeadSeconds;
      final offAt = _clamp(rawOffAt, earliest).clamp(onAt, double.infinity);
      midi.add(ScheduledMidi(onAt, 0x90 | e.channel, e.pitch, e.velocity));
      midi.add(ScheduledMidi(offAt, 0x80 | e.channel, e.pitch, 0));
    }
    _scheduledUpToMs = horizonMs;
    if (midi.isNotEmpty) engine.schedule(midi);

    // Todo evento que ainda faltava já entrou na agenda: não há mais nada
    // para o Timer fazer.
    if (horizonMs >= track.durationMs) {
      _timer?.cancel();
      _timer = null;
    }
  }

  double _clamp(double at, double earliest) => at < earliest ? earliest : at;
}

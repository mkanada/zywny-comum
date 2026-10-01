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
//
// LOOP A-B (T04): com [setLoop], quando o horizonte de [pump] alcança o fim do
// trecho o agendador fecha a volta (note-offs cortados em `endMs`, nada
// depois dele) e já **reancora** em `startMs` no instante de dispositivo em
// que `endMs` soa — a volta seguinte é agendada em seguida, sem lacuna. A
// âncora antiga fica em [_segments] até esse instante chegar, para que
// [positionMs] (que o `ScorePlayer` lê) só volte a `startMs` quando o áudio
// volta. O `ScorePlayer` percebe o recuo (> 20 ms) e faz `seek` sozinho.
// Mudança de `speed` no meio do loop vale na hora (reancora da posição
// corrente, como sempre).
//
// METRÔNOMO e CONTAGEM (T04): cliques no canal 9 nas [beats] (o host as
// deriva do timemap, ver metronome.dart). A contagem inicial desloca a âncora
// para 1 compasso antes de `fromMs`: a posição fica parada em `fromMs` (piso)
// enquanto os cliques soam.
import 'dart:async';

import '../music/performance_track.dart';
import 'metronome.dart';
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

  /// Batidas do compasso (T04) — ver `metronomeBeats`. Vazias: sem
  /// metrônomo nem contagem.
  List<Beat> beats = const [];

  /// Metrônomo ligado: clica em cada batida enquanto toca.
  bool metronomeOn = false;

  /// Avisado (do [pump], até uma janela de [lookahead] antes de o som
  /// voltar) cada vez que uma volta do loop fecha; o argumento é o número
  /// de voltas completas desde [setLoop].
  void Function(int laps)? onLoop;

  double? _loopStartMs;
  double? _loopEndMs;
  int _laps = 0;

  /// Saltos de caminho (J08): trechos `[startMs, endMs)` que o [pump] pula —
  /// ao alcançar `startMs`, reancora em `endMs` (como a volta do loop, sem
  /// lacuna) e avisa por [onJump]. Nada dentro deles é agendado (nem notas,
  /// nem cliques). Mutuamente exclusivos com o loop.
  List<({double startMs, double endMs})> _jumps = const [];
  int _jumpsTaken = 0;

  /// Avisado (do [pump]) a cada salto de caminho, com o destino em ms
  /// musicais — o host leva o `ScorePlayer` para lá, como em [onLoopRestart]
  /// (só que para a frente).
  void Function(double toMs)? onJump;

  /// Saltos dados desde [setJumps].
  int get jumpCount => _jumpsTaken;

  /// Âncoras antigas ainda audíveis: até `until` (segundos do dispositivo)
  /// [positionMs] usa esta âncora em vez da atual.
  final List<_Segment> _segments = [];

  /// Piso da posição durante a contagem inicial.
  double? _floorMs;
  List<Beat> _countIn = const [];

  /// Filtro de pauta do modo espera (T02): quando não-nulo, só eventos
  /// dessas pautas entram em [pump] — é assim que "o app toca a outra mão"
  /// (a pauta do aluno nunca é agendada, ele toca fisicamente).
  Set<int>? _staves;

  /// Teto de passagem única (J04): com [setStopAt], nada com `onMs >=` o teto
  /// é agendado (nem notas do app, nem cliques) e os `offMs` são cortados
  /// nele — mas a posição continua correndo (ao contrário do freio), para o
  /// último toque ainda poder casar dentro da folga. Mutuamente exclusivo
  /// com o loop.
  double? _stopAtMs;

  /// Teto de agendamento da passagem única, ou `null` sem teto.
  double? get stopAt => _stopAtMs;

  double get speed => _speed;
  bool get isRunning => _running;

  /// Posição musical atual, em ms — parada (o valor da última âncora)
  /// enquanto não [isRunning], e capada em [_brakeMs] quando o freio do
  /// modo espera está armado.
  double get positionMs {
    if (!_running) return _musicalT0;
    var raw = _rawPositionAt(engine.nowSeconds);
    final brake = _brakeMs;
    if (brake != null && raw > brake) raw = brake;
    final loopEnd = _loopEndMs;
    if (loopEnd != null && _segments.isEmpty && raw > loopEnd) raw = loopEnd;
    final floor = _floorMs;
    if (floor != null && raw < floor) raw = floor;
    return raw;
  }

  /// Posição musical que o relógio do dispositivo marcava (ou marcará) em
  /// [deviceSeconds], pela âncora corrente — para converter o carimbo de uma
  /// tecla em tempo musical (T03).
  double musicalAtDevice(double deviceSeconds) => _musicalAt(deviceSeconds);

  /// Trecho em repetição (T04), ou `null`.
  ({double startMs, double endMs})? get loop {
    final s = _loopStartMs;
    final e = _loopEndMs;
    return s == null || e == null ? null : (startMs: s, endMs: e);
  }

  /// Voltas do loop completadas desde [setLoop].
  int get loopLaps => _laps;

  /// Repete `[startMs, endMs)` (T04). Não move a posição: o host faz
  /// `seek(startMs)` se quiser começar pelo trecho. [clearLoop] desliga.
  void setLoop(double startMs, double endMs) {
    assert(endMs > startMs);
    _loopStartMs = startMs;
    _loopEndMs = endMs;
    _laps = 0;
  }

  void clearLoop() {
    _loopStartMs = null;
    _loopEndMs = null;
    _laps = 0;
  }

  /// Saltos de caminho para o [pump] pular, em ordem de tempo, sem
  /// sobreposição e com `startMs < endMs` — os intervalos que a trilha pula
  /// (casas não finais, voltas descartadas). Não move a posição: o salto
  /// acontece quando o horizonte alcança `startMs`. [clearJumps] desliga.
  void setJumps(List<({double startMs, double endMs})> jumps) {
    assert(
      _loopStartMs == null,
      'saltos e loop A-B são mutuamente exclusivos',
    );
    var prevEnd = double.negativeInfinity;
    for (final jump in jumps) {
      assert(jump.startMs < jump.endMs, 'salto precisa de startMs < endMs');
      assert(
        jump.startMs >= prevEnd,
        'saltos em ordem e sem sobreposição',
      );
      prevEnd = jump.endMs;
    }
    _jumps = List.of(jumps);
    _jumpsTaken = 0;
  }

  void clearJumps() {
    _jumps = const [];
    _jumpsTaken = 0;
  }

  double _rawPositionAt(double deviceSeconds) {
    _segments.removeWhere((s) => s.until <= deviceSeconds);
    if (_segments.isNotEmpty) {
      final s = _segments.first;
      return s.musicalT0 + (deviceSeconds - s.deviceT0) * 1000 * _speed;
    }
    return _musicalAt(deviceSeconds);
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

  /// Teto de agendamento da passagem única (J04): nada com `onMs >= [ms]` é
  /// agendado. [clearStopAt] desliga.
  void setStopAt(double ms) {
    _stopAtMs = ms;
  }

  void clearStopAt() {
    _stopAtMs = null;
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
    _segments.clear();
    _floorMs = null;
    _countIn = const [];
  }

  void _armTimer() {
    if (_autoTick) _timer ??= Timer.periodic(tickInterval, (_) => pump());
  }

  /// Começa (ou retoma) a tocar a partir de [fromMs]. Manda o Program
  /// Change de cada canal (uma vez, aqui) e liga a agenda.
  ///
  /// [countIn]: antes de [fromMs], 1 compasso de cliques (a contagem inicial,
  /// T04) — a posição fica parada em [fromMs] enquanto eles soam.
  void play(double fromMs, {double? speed, bool countIn = false}) {
    engine.allNotesOff();
    _reanchor(fromMs, speed: speed);
    if (countIn) {
      final clicks = countInBeats(beats, fromMs);
      if (clicks.isNotEmpty) {
        _countIn = clicks;
        _floorMs = fromMs;
        _musicalT0 = clicks.first.ms;
        _scheduledUpToMs = clicks.first.ms;
      }
    }
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

    final horizonDevice = engine.nowSeconds + lookahead.inMicroseconds / 1e6;
    final brake = _brakeMs;
    double horizon() {
      final raw = _musicalAt(horizonDevice);
      return brake == null || raw < brake ? raw : brake;
    }

    final earliest = engine.earliestScheduleSeconds;
    final midi = <ScheduledMidi>[];
    var horizonMs = horizon();

    // Fecha as voltas do loop que cabem na janela. Cada volta tem que
    // avançar (start < end e a âncora anda para `startMs`), então o laço
    // termina; o teto protege de um loop ínfimo com o relógio parado.
    final loopStart = _loopStartMs;
    final loopEnd = _loopEndMs;
    if (loopStart != null && loopEnd != null) {
      var guard = 0;
      while (_scheduledUpToMs < loopEnd &&
          horizonMs >= loopEnd &&
          guard++ < 64) {
        _emit(midi, _scheduledUpToMs, loopEnd, earliest, cutMs: loopEnd);
        final wrapDevice = _deviceAt(loopEnd);
        _segments.add(_Segment(wrapDevice, _deviceT0, _musicalT0));
        _musicalT0 = loopStart;
        _deviceT0 = wrapDevice;
        _scheduledUpToMs = loopStart;
        _laps++;
        onLoop?.call(_laps);
        horizonMs = horizon();
      }
    }

    // Fecha os saltos de caminho que cabem na janela: igual à volta do
    // loop, mas para a frente — ao alcançar o início, emite até ele (com os
    // `offMs` cortados) e reancora no destino no instante em que o início
    // soa, sem lacuna. Cada salto avança, então o laço termina.
    if (_jumps.isNotEmpty) {
      var guard = 0;
      while (guard++ < 64) {
        ({double startMs, double endMs})? gap;
        for (final jump in _jumps) {
          if (jump.startMs >= _scheduledUpToMs &&
              horizonMs >= jump.startMs) {
            gap = jump;
            break;
          }
        }
        if (gap == null) break;
        final g = gap;
        _emit(
          midi,
          _scheduledUpToMs,
          g.startMs,
          earliest,
          cutMs: g.startMs,
          stopAt: _stopAtMs,
        );
        final jumpDevice = _deviceAt(g.startMs);
        _segments.add(_Segment(jumpDevice, _deviceT0, _musicalT0));
        _musicalT0 = g.endMs;
        _deviceT0 = jumpDevice;
        _scheduledUpToMs = g.endMs;
        _jumpsTaken++;
        onJump?.call(g.endMs);
        horizonMs = horizon();
      }
    }

    if (horizonMs > _scheduledUpToMs) {
      _emit(
        midi,
        _scheduledUpToMs,
        horizonMs,
        earliest,
        cutMs: loopEnd != null && horizonMs > loopEnd
            ? loopEnd
            : (_stopAtMs != null && horizonMs > _stopAtMs! ? _stopAtMs : null),
        stopAt: _stopAtMs,
      );
      _scheduledUpToMs = horizonMs;
    }
    if (midi.isNotEmpty) engine.schedule(midi);

    // Todo evento que ainda faltava já entrou na agenda: não há mais nada
    // para o Timer fazer (com loop, nunca acaba).
    if (loopEnd == null && horizonMs >= track.durationMs) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Agenda em [midi] o que começa em `[lo, hi)`: notas (com `offMs`
  /// cortado em [cutMs]), cliques do metrônomo e da contagem inicial.
  /// [stopAt] (teto da passagem única, J04) capa o `onMs` de notas e cliques
  /// — a posição continua correndo além dele.
  void _emit(
    List<ScheduledMidi> midi,
    double lo,
    double hi,
    double earliest, {
    double? cutMs,
    double? stopAt,
  }) {
    final floor = _floorMs;
    final noteLo = floor != null && lo < floor ? floor : lo;
    final noteHi = stopAt != null && hi > stopAt ? stopAt : hi;
    if (noteHi > noteLo) {
      for (final e in track.startingIn(noteLo, noteHi, staves: _staves)) {
        // Atrasado (tick perdido, GC): nunca descarte o par — toque no mais
        // cedo possível.
        final onAt = _clamp(_deviceAt(e.onMs), earliest);
        final offMs = cutMs != null && e.offMs > cutMs ? cutMs : e.offMs;
        final rawOffAt = _deviceAt(offMs) - _kNoteOffLeadSeconds;
        final offAt = _clamp(rawOffAt, earliest).clamp(onAt, double.infinity);
        midi.add(ScheduledMidi(onAt, 0x90 | e.channel, e.pitch, e.velocity));
        midi.add(ScheduledMidi(offAt, 0x80 | e.channel, e.pitch, 0));
      }
    }
    for (final b in _countIn) {
      if (b.ms >= lo && b.ms < hi && (stopAt == null || b.ms < stopAt)) {
        _click(midi, b, earliest);
      }
    }
    if (metronomeOn) {
      for (final b in beats) {
        if (b.ms >= hi) break;
        if (stopAt != null && b.ms >= stopAt) break;
        if (b.ms >= lo && (floor == null || b.ms >= floor)) {
          _click(midi, b, earliest);
        }
      }
    }
  }

  void _click(List<ScheduledMidi> midi, Beat b, double earliest) {
    final at = _clamp(_deviceAt(b.ms), earliest);
    final note = b.accent ? kMetronomeAccentNote : kMetronomeNote;
    midi.add(ScheduledMidi(at, 0x90 | kMetronomeChannel, note, 100));
    midi.add(ScheduledMidi(at + 0.05, 0x80 | kMetronomeChannel, note, 0));
  }

  double _clamp(double at, double earliest) => at < earliest ? earliest : at;
}

class _Segment {
  const _Segment(this.until, this.deviceT0, this.musicalT0);

  final double until;
  final double deviceT0;
  final double musicalT0;
}

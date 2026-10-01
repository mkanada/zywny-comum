// T02: liga MidiInputService -> WaitModeSession (T01) -> cores do
// ScoreController + freio do ScoreAudioScheduler (K04) + teclado desenhado
// (M01). Ao contrário de practice_session.dart (T01, Dart puro), esta
// classe é Flutter-aware de propósito — é a cola entre hardware/UI e o
// núcleo puro.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart';

import '../audio/score_audio_scheduler.dart';
import '../audio/sound_engine.dart';
import '../midi/midi_input_service.dart';
import '../midi/midi_monitor.dart' show kMidiMonitorChannel;
import '../music/performance_track.dart';
import '../trail/stage_result.dart';
import 'hand.dart';
import 'practice_colors.dart';
import 'practice_report.dart';
import 'practice_session.dart';
import 'rhythm_session.dart';

/// Como o treino conduz o tempo (T03).
enum PracticeMode {
  /// Modo espera (T02): o tempo para até o aluno tocar o passo.
  wait,

  /// Tempo real (T03): a música anda e cada nota recebe veredito na hora.
  realtime,

  /// Ritmo (T05): a música anda e o aluno aperta qualquer tecla no instante
  /// de cada ataque; só o tempo é avaliado.
  rhythm,
}

/// Modo espera (T02): o aluno escolhe [hand], o app agenda a outra no
/// [scheduler] (freio incluso) e cada nota tocada no [midiInput] alimenta o
/// [WaitModeSession] — que devolve as cores certo/errado para o
/// [ScoreController] e o pitch errado para o teclado desenhado.
class PracticeController {
  PracticeController({
    required MidiInputService midiInput,
    required PerformanceTrack track,
    required this.scheduler,
    required this.controller,
    required this.hand,
    this.ghosts,
    this.inputLatencyMs = 0,
    this.onLoopRestart,
    this.mode = PracticeMode.wait,
    this.measureIndexAt,
    this.passOf,
    this.magicEngine,
    this.range,
    this.onRangeDone,
    this.rangeJumps = const [],
    this.onRangeJump,
  }) : _midiInput = midiInput, // ignore: prefer_initializing_formals
       _track = track {
    if (range != null) {
      assert(
        range!.startMs < range!.endMs,
        'range precisa de startMs < endMs',
      );
    }
    _noteSub = _midiInput.notes.listen(_onNote);
    // As sessões avaliam só o que toca: no intervalo, sem os saltos (J08).
    // Sem `range`, é a peça inteira — igual a antes.
    final activeRange = range;
    final sessionTrack = activeRange == null
        ? track
        : track.rangeView(
            startMs: activeRange.startMs,
            endMs: activeRange.endMs,
            gaps: rangeJumps,
          );
    if (mode == PracticeMode.wait) {
      final wait = WaitModeSession.forStaves(
        sessionTrack,
        staves: hand.studentStaves,
      );
      _wait = wait;
      if (range != null) _tally = WaitTally();
      _verdictSub = wait.verdicts.listen(_onVerdict);
      wait.current.addListener(_onStepChanged);
      _syncGhostExpected();
    } else if (mode == PracticeMode.rhythm) {
      final rhythm = RhythmSession.forStaves(
        sessionTrack,
        staves: hand.studentStaves,
        speed: scheduler.speed,
      );
      _rhythm = rhythm;
      _rhythmSub = rhythm.verdicts.listen(_onRhythmVerdict);
    } else {
      final rt = RealtimeSession.forStaves(
        sessionTrack,
        staves: hand.studentStaves,
        speed: scheduler.speed,
      );
      _rt = rt;
      _verdictSub = rt.verdicts.listen(_onVerdict);
    }
  }

  final PracticeMode mode;

  /// Compasso (ocorrência, índice de `ScoreTimeline.measures`) em `ms`
  /// musicais — para o [report]. `null`: tudo cai no compasso 0.
  final int Function(double ms)? measureIndexAt;

  /// Passagem (`MeasureInfo.pass`) de uma ocorrência — para o resumo dizer
  /// "2ª vez". `null`: sempre 1.
  final int Function(int measureIndex)? passOf;
  final PerformanceTrack _track;

  /// Modo ritmo, "piano mágico" (D-RITMO a): o toque que casa soa as notas
  /// esperadas do onset neste motor, no canal do monitor. `null`: mudo (o
  /// piano digital com saída MIDI, M03, soa a tecla real por conta própria).
  final SoundEngine? magicEngine;

  final MidiInputService _midiInput;
  final ScoreAudioScheduler scheduler;
  final ScoreController controller;
  final Hand hand;

  /// Nota fantasma (G05): cada tecla errada apertada vira uma cabeça de nota
  /// na pauta, na coluna do passo atual. `null` desliga.
  final GhostController? ghosts;

  /// Latência de entrada+saída calibrada (T04), em ms: descontada do carimbo
  /// de cada tecla antes de chegar à sessão.
  final double inputLatencyMs;

  /// Chamado quando o loop A-B recomeça (o aluno terminou o trecho): o host
  /// leva o `ScorePlayer` para `startMs` (o agendador já foi reposto aqui).
  final void Function(double startMs)? onLoopRestart;

  /// Intervalo de passagem única (J04): tocar `[startMs, endMs)` uma vez,
  /// parar sozinho no fim e entregar um [stageResult]. Mutuamente exclusivo
  /// com o loop ([setLoop] com `range` é erro de programação). `null` é o
  /// modo livre de hoje (sem fim próprio).
  final ({double startMs, double endMs})? range;

  /// Saltos dentro de [range] (J08): intervalos que o agendador pula e as
  /// sessões nem avaliam (casas descartadas, voltas). Vazio sem saltos.
  final List<({double startMs, double endMs})> rangeJumps;

  /// Chamado uma vez, quando o intervalo termina por conta própria (não num
  /// `stop` no meio — esse a tela trata como tentativa abandonada).
  final void Function()? onRangeDone;

  /// Chamado a cada salto de caminho com o destino (o host leva o
  /// `ScorePlayer` para lá, como em [onLoopRestart]).
  final void Function(double toMs)? onRangeJump;

  double? _loopStartMs;
  double? _loopEndMs;

  /// Contagem do modo espera na passagem única (J02): passos de primeira /
  /// passos concluídos. Só existe com `range` no modo espera.
  WaitTally? _tally;

  /// Passo do aluno que o [_tally] tem como pendente (`null` sem pendência
  /// contabilizada).
  int? _tallyStep;

  /// O intervalo terminou por conta própria ([onRangeDone] já foi chamado).
  bool _rangeDone = false;
  WaitModeSession? _wait;
  RealtimeSession? _rt;
  RhythmSession? _rhythm;
  StreamSubscription<RhythmVerdict>? _rhythmSub;

  late final StreamSubscription<PlayedNote> _noteSub;
  StreamSubscription<NoteVerdict>? _verdictSub;
  Timer? _tickTimer;

  final ValueNotifier<Set<int>> _wrongPitches = ValueNotifier(const {});
  final ValueNotifier<int> _correctCount = ValueNotifier(0);
  final ValueNotifier<int> _wrongCount = ValueNotifier(0);

  /// Acertos e erros da sessão, para os contadores da tela (o artefato
  /// mostra "23 · ×1"). Só contam veredictos do modo espera.
  ValueListenable<int> get correctCount => _correctCount;
  ValueListenable<int> get wrongCount => _wrongCount;

  /// Passo pendente do aluno (para a UI mostrar progresso); `null` quando a
  /// sessão acabou.
  ValueListenable<PracticeStep?> get currentStep => _wait?.current ?? _noStep;
  static final ValueNotifier<PracticeStep?> _noStep = ValueNotifier(null);

  /// Pitches errados apertados agora — o teclado desenhado (M01) pinta em
  /// vermelho.
  ValueListenable<Set<int>> get wrongPitches => _wrongPitches;

  bool get done => _wait?.done ?? false;

  /// Modo espera: arma o freio no primeiro passo. Tempo real: sem freio, a
  /// música anda. Nos dois, filtra o agendador para a mão do app (vazio em
  /// [Hand.ambas] — o app não toca nada) e começa em [fromMs].
  ///
  /// [fromMs] começa no meio da peça (loop A-B); [countIn] antecede com 1
  /// compasso de cliques (T04). Com [range], começa em `range.startMs` e o
  /// teto de áudio vai para `range.endMs`.
  void start({double fromMs = 0, bool countIn = false}) {
    scheduler.setStaves(hand.appStaves);
    final range = this.range;
    final wait = _wait;
    if (wait != null) {
      if (range != null) {
        wait.resetTo(range.startMs);
        scheduler.setBrake(wait.current.value?.onMs);
        scheduler.setStopAt(range.endMs);
        scheduler.setJumps(rangeJumps);
        scheduler.onJump = onRangeJump;
      } else {
        if (fromMs > 0) wait.resetTo(fromMs);
        scheduler.setBrake(wait.current.value?.onMs);
      }
    } else {
      final startMs = range?.startMs ?? fromMs;
      _resetTimed(startMs, untilMs: _loopEndMs ?? range?.endMs);
      scheduler.setBrake(null);
      if (range != null) {
        scheduler.setStopAt(range.endMs);
        scheduler.setJumps(rangeJumps);
        scheduler.onJump = onRangeJump;
      }
      _lastPositionMs = startMs;
      _tickTimer ??= Timer.periodic(
        const Duration(milliseconds: 30),
        (_) => _tick(),
      );
    }
    // Intervalo sem passo/evento (só pausa): o reset acima já terminou.
    if (_rangeDone) return;
    scheduler.play(range?.startMs ?? fromMs, countIn: countIn);
  }

  /// Loop A-B no treino (T04). Espera: ao passar o último passo de
  /// `[startMs, endMs)` a sessão recomeça em `startMs` (o agendador é
  /// reposto) e o host é avisado por [onLoopRestart]. Tempo real: o agendador
  /// dá as voltas; a cada volta o que faltou vira `missed` e a avaliação
  /// recomeça. [clearLoop] desliga.
  void setLoop(double startMs, double endMs) {
    assert(
      range == null,
      'loop e passagem única (range) são mutuamente exclusivos',
    );
    _loopStartMs = startMs;
    _loopEndMs = endMs;
    final wait = _wait;
    if (wait != null) {
      final step = wait.current.value;
      if (step == null || step.onMs >= endMs) _restartLoop();
    } else {
      _resetTimed(startMs, untilMs: endMs);
    }
  }

  void clearLoop() {
    _loopStartMs = null;
    _loopEndMs = null;
    if (_timed) _resetTimed(_lastPositionMs);
  }

  bool _restarting = false;

  void _restartLoop() {
    final start = _loopStartMs;
    final wait = _wait;
    if (start == null || wait == null || _restarting) return;
    _restarting = true;
    scheduler.seek(start);
    wait.resetTo(start);
    _restarting = false;
    scheduler.setBrake(wait.current.value?.onMs);
    onLoopRestart?.call(start);
  }

  // -------------------------------------------------------------------------
  // Tempo real (T03)
  // -------------------------------------------------------------------------

  double _lastPositionMs = 0;

  /// Verdicts da sessão + o compasso de cada um, para o [report].
  final List<ReportEntry> _entries = [];

  /// Resumo do que foi avaliado até agora.
  PracticeReport get report => _rhythm != null
      ? PracticeReport.rhythm(_rhythmEntries, speed: scheduler.speed)
      : PracticeReport(_entries, speed: scheduler.speed);

  /// `true` se já houve algum veredito (para decidir se vale mostrar o
  /// resumo).
  bool get hasVerdicts => _entries.isNotEmpty || _rhythmEntries.isNotEmpty;

  /// Chamado ~a cada 30 ms no tempo real: dispara os `missed`, fecha a volta
  /// do loop quando a posição recua e sinaliza o fim da peça.
  bool get _timed => _rt != null || _rhythm != null;

  void _resetTimed(double fromMs, {double? untilMs}) {
    _rt?.resetTo(fromMs, untilMs: untilMs);
    _rhythm?.resetTo(fromMs, untilMs: untilMs);
  }

  void _tickTimed(double ms) {
    _rt?.tick(ms);
    _rhythm?.tick(ms);
  }

  /// Folga (ms musicais) depois da qual um alvo sem toque vira `missed`.
  double get _slackMs {
    final rt = _rt;
    if (rt != null) return rt.windowMaxMs * rt.speed;
    final r = _rhythm!;
    return r.windowMaxMs * r.speed;
  }

  void _tick() {
    if (!_timed || !scheduler.isRunning) return;
    final pos = scheduler.positionMs;
    final range = this.range;
    if (range != null) {
      // Passagem única: a posição passa do fim + folga (o último toque
      // ainda pode casar), aí o que faltou vira `missed` e termina sozinho.
      if (pos >= range.endMs + _slackMs) {
        _tickTimed(range.endMs + _slackMs + 1);
        _finishRange();
      } else {
        _lastPositionMs = pos;
        _tickTimed(pos);
      }
      return;
    }
    final loopEnd = _loopEndMs;
    final loopStart = _loopStartMs;
    if (loopEnd != null && loopStart != null && pos < _lastPositionMs - 1) {
      // Voltou ao início do trecho: o que sobrou da volta anterior foi
      // perdido; começa a volta nova do zero.
      _tickTimed(loopEnd + _slackMs + 1);
      _resetTimed(loopStart, untilMs: loopEnd);
      _lastPositionMs = pos;
      return;
    }
    _lastPositionMs = pos;
    _tickTimed(pos);
    if (loopEnd == null && pos >= _track.durationMs) {
      _tickTimed(pos + _slackMs + 1);
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  /// Fecha a avaliação (o que faltava vira `missed`) — chamar ao terminar ou
  /// parar, antes de ler [report].
  void finish() {
    if (!_timed) return;
    final end = _loopEndMs ?? range?.endMs ?? _track.durationMs;
    final pos = scheduler.positionMs;
    // Só o que já devia ter soado conta como perdido ao parar no meio.
    _tickTimed(pos >= end ? end + _slackMs + 1 : pos);
  }

  /// O intervalo terminou por conta própria: silencia, solta tudo e avisa o
  /// host uma vez. O [stageResult] continua válido depois daqui.
  void _finishRange() {
    if (_rangeDone) return;
    _rangeDone = true;
    stop();
    onRangeDone?.call();
  }

  /// Resultado da passagem única — válido depois do fim do intervalo ou de
  /// [finish()]. Parar no meio (`stop` antes do fim) dá o parcial avaliado
  /// até ali (`null` se nada foi avaliado ainda); sem [range], `null`.
  StageResult? get stageResult {
    final range = this.range;
    if (range == null) return null;
    final tally = _tally;
    if (tally != null) {
      final result = tally.result();
      if (result.total > 0 || _rangeDone) return result;
      return null;
    }
    if (hasVerdicts || _rangeDone) {
      return StageResult.fromReport(
        report,
        rhythm: mode == PracticeMode.rhythm,
      );
    }
    return null;
  }

  /// Solta o freio/filtro e para o agendador — volta ao comportamento
  /// normal de playback.
  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    scheduler.setBrake(null);
    scheduler.setStaves(null);
    scheduler.clearStopAt();
    scheduler.clearJumps();
    scheduler.onJump = null;
    scheduler.pause();
    _releaseMagic();
    controller.releaseAll();
    ghosts?.clear();
    _wrongPitches.value = const {};
  }

  void _onNote(PlayedNote note) {
    final wait = _wait;
    if (note.on) {
      if (wait != null) {
        wait.noteOn(
          note.pitch,
          atMs: note.atSeconds * 1000 - inputLatencyMs,
          velocity: note.velocity,
        );
      } else {
        final musicalMs = scheduler.musicalAtDevice(
          note.atSeconds - inputLatencyMs / 1000,
        );
        _lastPlayedMusicalMs = musicalMs;
        final rhythm = _rhythm;
        if (rhythm != null) {
          _keysDown++;
          _pressVelocity = note.velocity;
          rhythm.hit(
            musicalMs,
            atMs: note.atSeconds * 1000 - inputLatencyMs,
            velocity: note.velocity,
          );
        } else {
          _rt!.noteOn(note.pitch, musicalMs, velocity: note.velocity);
        }
      }
    } else {
      if (_rhythm != null) {
        _keysDown = math.max(0, _keysDown - 1);
        if (_keysDown == 0) _releaseMagic();
        _rhythm!.release(
          scheduler.musicalAtDevice(note.atSeconds - inputLatencyMs / 1000),
        );
      }
      wait?.noteOff(note.pitch);
      ghosts?.release(note.pitch);
      if (_wrongPitches.value.contains(note.pitch)) {
        _wrongPitches.value = Set.of(_wrongPitches.value)..remove(note.pitch);
      }
    }
  }

  double _lastPlayedMusicalMs = 0;

  // -------------------------------------------------------------------------
  // Ritmo (T05)
  // -------------------------------------------------------------------------

  final List<RhythmReportEntry> _rhythmEntries = [];
  final ValueNotifier<int> _extraBlink = ValueNotifier(0);
  int _keysDown = 0;
  int _pressVelocity = 80;
  final List<int> _magicPitches = [];
  Map<String, int>? _pitchById;

  /// Sobe a cada toque sem alvo (`extra`): a UI pisca o indicador de toque.
  ValueListenable<int> get extraBlink => _extraBlink;

  void _releaseMagic() {
    final engine = magicEngine;
    if (engine != null) {
      for (final p in _magicPitches) {
        engine.send([0x80 | kMidiMonitorChannel, p, 0]);
      }
    }
    _magicPitches.clear();
  }

  void _soundMagic(List<String> eventIds, int velocity) {
    final engine = magicEngine;
    if (engine == null) return;
    _releaseMagic();
    final map = _pitchById ??= {for (final e in _track.events) e.id: e.pitch};
    final v = velocity > 0 ? velocity : _pressVelocity;
    for (final id in eventIds) {
      final pitch = map[id];
      if (pitch == null) continue;
      _magicPitches.add(pitch);
      engine.send([0x90 | kMidiMonitorChannel, pitch, v]);
    }
  }

  void _onRhythmVerdict(RhythmVerdict v) {
    final ms = v.onMs ?? _lastPlayedMusicalMs;
    final index = measureIndexAt?.call(ms) ?? 0;
    _rhythmEntries.add(
      RhythmReportEntry(v, index, pass: passOf?.call(index) ?? 1),
    );
    final (color, release) = switch (v.kind) {
      RhythmVerdictKind.correct => (kPracticeCorrectColor, null),
      RhythmVerdictKind.early ||
      RhythmVerdictKind.late => (kPracticeOffBeatColor, null),
      _ => (kPracticeMissedColor, kPracticeMissedHold),
    };
    switch (v.kind) {
      case RhythmVerdictKind.correct:
      case RhythmVerdictKind.early:
      case RhythmVerdictKind.late:
        _correctCount.value++;
        _soundMagic(v.eventIds, v.velocity);
        for (final id in v.eventIds) {
          controller.highlight(
            id,
            color: color,
            release: kPracticeCorrectRelease,
          );
        }
      case RhythmVerdictKind.missed:
        for (final id in v.eventIds) {
          controller.highlight(
            id,
            color: color,
            attack: kPracticeWrongAttack,
            hold: release!,
            release: kPracticeWrongRelease,
          );
        }
      case RhythmVerdictKind.extra:
        _wrongCount.value++;
        _extraBlink.value++;
    }
  }

  Map<String, double>? _onMsById;

  double _eventOnMs(String id) {
    final map = _onMsById ??= {for (final e in _track.events) e.id: e.onMs};
    return map[id] ?? 0;
  }

  void _record(NoteVerdict verdict) {
    final ms = verdict.eventId != null
        ? _eventOnMs(verdict.eventId!)
        : (_wait?.current.value?.onMs ?? _lastPlayedMusicalMs);
    final index = measureIndexAt?.call(ms) ?? 0;
    _entries.add(ReportEntry(verdict, index, pass: passOf?.call(index) ?? 1));
  }

  void _onVerdict(NoteVerdict verdict) {
    _record(verdict);
    if (verdict.kind == PracticeVerdictKind.wrong) _tally?.wrong();
    switch (verdict.kind) {
      case PracticeVerdictKind.correct:
        _correctCount.value++;
        if (verdict.eventId != null) {
          controller.highlight(
            verdict.eventId!,
            color: kPracticeCorrectColor,
            release: kPracticeCorrectRelease,
          );
        }
      case PracticeVerdictKind.wrong:
        _wrongCount.value++;
        _wrongPitches.value = Set.of(_wrongPitches.value)..add(verdict.pitch);
        ghosts?.press(verdict.pitch);
        final nearestId = _wait != null
            ? _nearestExpectedId(verdict.pitch)
            : _nearestEventId(verdict.pitch, _lastPlayedMusicalMs);
        if (nearestId != null) {
          controller.highlight(
            nearestId,
            color: kPracticeWrongColor,
            attack: kPracticeWrongAttack,
            hold: kPracticeWrongHold,
            release: kPracticeWrongRelease,
          );
        }
      case PracticeVerdictKind.early:
      case PracticeVerdictKind.late:
        _correctCount.value++;
        if (verdict.eventId != null) {
          controller.highlight(
            verdict.eventId!,
            color: kPracticeOffBeatColor,
            release: kPracticeCorrectRelease,
          );
        }
      case PracticeVerdictKind.missed:
        if (verdict.eventId != null) {
          controller.highlight(
            verdict.eventId!,
            color: kPracticeMissedColor,
            attack: kPracticeWrongAttack,
            hold: kPracticeMissedHold,
            release: kPracticeWrongRelease,
          );
        }
    }
  }

  /// Tempo real: id do evento do aluno mais perto em pitch entre os que
  /// soam a até 400 ms musicais de [ms].
  String? _nearestEventId(int wrongPitch, double ms) {
    SoundEvent? nearest;
    var bestDistance = 1 << 30;
    for (final e in _track.startingIn(
      ms - 400,
      ms + 400,
      staves: hand.studentStaves,
    )) {
      final distance = (e.pitch - wrongPitch).abs();
      if (distance < bestDistance) {
        nearest = e;
        bestDistance = distance;
      }
    }
    return nearest?.id;
  }

  /// Id da nota esperada mais próxima em pitch de [wrongPitch], entre as
  /// que ainda faltam no passo atual — a nota errada em si pode não existir
  /// na partitura.
  String? _nearestExpectedId(int wrongPitch) {
    final step = _wait?.current.value;
    if (step == null) return null;
    SoundEvent? nearest;
    var bestDistance = 1 << 30;
    for (final e in step.notes) {
      if (!step.remaining.contains(e.pitch)) continue;
      final distance = (e.pitch - wrongPitch).abs();
      if (distance < bestDistance) {
        nearest = e;
        bestDistance = distance;
      }
    }
    return nearest?.id;
  }

  void _onStepChanged() {
    final wait = _wait;
    if (wait == null) return;
    final range = this.range;
    if (range != null) {
      // Passagem única: o passo anterior concluiu quando o índice troca (a
      // republicação do mesmo passo a cada nota certa não conta); o
      // seguinte, se ainda está no intervalo, entra na contagem — senão o
      // intervalo acabou.
      final step = wait.current.value;
      if (step == null || step.onMs >= range.endMs) {
        if (_tallyStep != null) {
          _tally?.stepDone();
          _tallyStep = null;
        }
        _finishRange();
        return;
      }
      if (_tallyStep == step.index) return;
      if (_tallyStep != null) _tally?.stepDone();
      _tally?.stepStarted(step.index, measureIndexAt?.call(step.onMs) ?? 0);
      _tallyStep = step.index;
      scheduler.setBrake(step.onMs);
      _syncGhostExpected();
      return;
    }
    final end = _loopEndMs;
    if (end != null) {
      final step = wait.current.value;
      if (step == null || step.onMs >= end) {
        _restartLoop();
        return;
      }
    }
    scheduler.setBrake(wait.current.value?.onMs);
    _syncGhostExpected();
  }

  /// Todas as notas do passo (não só as que faltam): a colisão da fantasma
  /// com as cabeças reais da coluna precisa conhecê-las (G05, §10 passo 7).
  void _syncGhostExpected() {
    final step = _wait?.current.value;
    ghosts?.setExpected([
      if (step != null)
        for (final e in step.notes) e.id,
    ]);
  }

  void dispose() {
    _tickTimer?.cancel();
    unawaited(_noteSub.cancel());
    unawaited(_verdictSub?.cancel());
    unawaited(_rhythmSub?.cancel());
    _releaseMagic();
    _wait?.current.removeListener(_onStepChanged);
    _wait?.dispose();
    _rt?.dispose();
    _rhythm?.dispose();
    _extraBlink.dispose();
    _wrongPitches.dispose();
    _correctCount.dispose();
    _wrongCount.dispose();
  }
}

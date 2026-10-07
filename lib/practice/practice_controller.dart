// T02: liga MidiInputService -> WaitModeSession (T01) -> cores do
// ScoreController + freio do ScoreAudioScheduler (K04) + teclado desenhado
// (M01). Ao contrário de practice_session.dart (T01, Dart puro), esta
// classe é Flutter-aware de propósito — é a cola entre hardware/UI e o
// núcleo puro.

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart';

import 'package:zywny_audio/score_audio_scheduler.dart';

import 'package:zywny_midi/midi_input_service.dart';

import 'package:zywny_audio/performance_track.dart';

import 'stage_result.dart';
import 'hand.dart';
import 'practice_colors.dart';
import 'practice_mode.dart';
import 'practice_report.dart';
import 'practice_session.dart';
import 'shift_detector.dart';

export 'practice_mode.dart';

/// Modo espera (T02): o aluno escolhe [hand], o app agenda a outra no
/// [scheduler] (freio incluso) e cada nota tocada no [midiInput] alimenta o
/// [WaitModeSession] — que devolve as cores esperada/certa para o
/// [ScoreController] (ver "três camadas" em [_paintStep]) e o pitch errado
/// para a fantasma e o teclado desenhado.
class PracticeController {
  PracticeController({
    required MidiInputService midiInput,
    required PerformanceTrack track,
    required this.scheduler,
    required this.controller,
    required this.hand,
    this.ghosts,
    this.inputLatencyMs = 0,
    this.writtenFromReceived = _samePitch,
    this.shiftDetector,
    this.onShift,
    this.onLoopRestart,
    this.mode = PracticeMode.wait,
    this.measureIndexAt,
    this.passOf,
    this.range,
    this.onRangeDone,
    this.rangeJumps = const [],
    this.onRangeJump,
    this.onWaitTarget,
    this.correctColor = kPracticeCorrectColor,
    this.wrongColor = kPracticeWrongColor,
    this._pendingColor = kPracticePendingColor,
    this.rhythmToleranceMs = kDefaultRhythmToleranceMs,
  }) : _midiInput = midiInput, // ignore: prefer_initializing_formals
       _track = track {
    if (range != null) {
      assert(range!.startMs < range!.endMs, 'range precisa de startMs < endMs');
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
      _paintStep();
      _syncGhostExpected();
    } else {
      final rt = RealtimeSession.forStaves(
        sessionTrack,
        staves: hand.studentStaves,
        speed: scheduler.speed,
        windowOkMs: rhythmToleranceMs,
        windowMaxMs: rhythmToleranceMs * 2,
      );
      _rt = rt;
      _verdictSub = rt.verdicts.listen(_onVerdict);
    }
  }

  final PracticeMode mode;

  /// Converte a altura que chegou do teclado na **escrita** (a da partitura):
  /// com a música transposta, o teclado pode mandar a soada (fase Q,
  /// `PitchFrame.writtenFromReceived`). O treino todo compara escrita com
  /// escrita. Chamada a cada nota, então vale o teclado e o tom de agora.
  final int Function(int received) writtenFromReceived;

  static int _samePitch(int pitch) => pitch;

  /// Q07: vê, a cada nota errada, se o teclado inteiro está deslocado (o
  /// TRANSPOSE errado). Cada nota errada leva as distâncias às esperadas;
  /// cada acerto zera a conta. `null` = não vigia.
  final ShiftDetector? shiftDetector;

  /// Chamado com a distância `d` (tocada − esperada, em altura escrita)
  /// quando [shiftDetector] dispara.
  final void Function(int d)? onShift;

  /// Cores da nota certa e do pulso de nota errada (configuráveis em
  /// Cores); mutáveis para o host trocar no meio do treino. Valem para o
  /// próximo veredito.
  Color correctColor;
  Color wrongColor;

  /// Modo espera: cor das notas do passo pendente (a camada do meio, ver
  /// [_paintStep]). Trocar recolore o passo atual na hora.
  Color get pendingColor => _pendingColor;
  Color _pendingColor;
  set pendingColor(Color value) {
    if (value == _pendingColor) return;
    _pendingColor = value;
    controller.setColors({for (final id in _expectedIds) id: value});
  }

  /// Compasso (ocorrência, índice de `ScoreTimeline.measures`) em `ms`
  /// musicais — para o [report]. `null`: tudo cai no compasso 0.
  final int Function(double ms)? measureIndexAt;

  /// Passagem (`MeasureInfo.pass`) de uma ocorrência — para o resumo dizer
  /// "2ª vez". `null`: sempre 1.
  final int Function(int measureIndex)? passOf;
  final PerformanceTrack _track;

  /// Tempo real: a margem (ms, no andamento original) para a nota contar
  /// como certa; até o dobro dela é "fora do tempo", além disso, perdida.
  /// Em ms musicais, então afrouxa junto com o andamento.
  final double rhythmToleranceMs;

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

  /// Modo espera: chamado a cada troca do freio com o instante (ms musicais)
  /// da nota pendente — `null` ao parar. O host repassa a
  /// `ScorePlayer.waitTarget`, que conclui a virada de página sem esperar o
  /// relógio (que fica parado no freio).
  final void Function(double? onMs)? onWaitTarget;

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

  final ValueNotifier<({int hits, int total})> _liveScore = ValueNotifier((
    hits: 0,
    total: 0,
  ));

  /// Acertos e total avaliado **até agora**, na mesma conta de
  /// [stageResult] (U05): modo espera com intervalo = passos de primeira /
  /// passos concluídos; tempo real = `correct` / avaliadas. Incremental,
  /// para não refazer o resumo a cada veredito. Sem resultado (modo espera
  /// sem intervalo): fica em 0/0.
  ValueListenable<({int hits, int total})> get liveScore => _liveScore;

  void _liveAdd({required bool hit}) {
    final now = _liveScore.value;
    _liveScore.value = (hits: now.hits + (hit ? 1 : 0), total: now.total + 1);
  }

  void _liveFromTally() {
    final tally = _tally;
    if (tally == null) return;
    _liveScore.value = (hits: tally.firstTry, total: tally.done);
  }

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
        // Sem nenhum passo no trecho (mão só com pausa): a sessão já nasce
        // sem passo e não avisa mudança nenhuma — encerra aqui, senão a
        // etapa tocaria sozinha e ficaria sem resumo.
        final first = wait.current.value;
        if (first == null || first.onMs >= range.endMs) {
          _finishRange();
          return;
        }
        _setBrake(wait.current.value?.onMs);
        scheduler.setStopAt(range.endMs - kRangeBoundaryToleranceMs);
        scheduler.setJumps(rangeJumps);
        scheduler.onJump = onRangeJump;
      } else {
        if (fromMs > 0) wait.resetTo(fromMs);
        _setBrake(wait.current.value?.onMs);
      }
    } else {
      final startMs = range?.startMs ?? fromMs;
      _resetTimed(startMs, untilMs: _loopEndMs ?? range?.endMs);
      scheduler.setBrake(null);
      if (range != null) {
        scheduler.setStopAt(range.endMs - kRangeBoundaryToleranceMs);
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
    scheduler.play(
      range == null ? fromMs : range.startMs - kRangeBoundaryToleranceMs,
      countIn: countIn,
    );
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

  /// Modo espera: arma (ou solta) o freio do agendador e avisa o host do
  /// instante da nota pendente ([onWaitTarget]).
  void _setBrake(double? onMs) {
    scheduler.setBrake(onMs);
    onWaitTarget?.call(onMs);
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
    _setBrake(wait.current.value?.onMs);
    onLoopRestart?.call(start);
  }

  // -------------------------------------------------------------------------
  // Tempo real (T03)
  // -------------------------------------------------------------------------

  double _lastPositionMs = 0;

  /// Verdicts da sessão + o compasso de cada um, para o [report].
  final List<ReportEntry> _entries = [];

  /// Resumo do que foi avaliado até agora.
  PracticeReport get report => PracticeReport(_entries, speed: scheduler.speed);

  /// `true` se já houve algum veredito (para decidir se vale mostrar o
  /// resumo).
  bool get hasVerdicts => _entries.isNotEmpty;

  /// Chamado ~a cada 30 ms no tempo real: dispara os `missed`, fecha a volta
  /// do loop quando a posição recua e sinaliza o fim da peça.
  bool get _timed => _rt != null;

  void _resetTimed(double fromMs, {double? untilMs}) {
    _rt?.resetTo(fromMs, untilMs: untilMs);
  }

  void _tickTimed(double ms) {
    _rt?.tick(ms);
  }

  /// Folga (ms musicais) depois da qual um alvo sem toque vira `missed`.
  double get _slackMs {
    return _rt!.windowMaxMs;
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
      if (result.total > 0) return result;
      if (!_rangeDone) return null;
      return StageResult(
        hits: 0,
        total: 0,
        badMeasures: const {},
        nothingToPlay: true,
      );
    }
    if (hasVerdicts || _rangeDone) {
      return StageResult.fromReport(report);
    }
    return null;
  }

  /// Solta o freio/filtro e para o agendador — volta ao comportamento
  /// normal de playback.
  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    if (_wait != null) {
      _setBrake(null);
    } else {
      scheduler.setBrake(null);
    }
    scheduler.setStaves(null);
    scheduler.clearStopAt();
    scheduler.clearJumps();
    scheduler.onJump = null;
    scheduler.pause();
    controller.releaseAll();
    _clearExpected();
    _paintedStep = null;
    _litStep.clear();
    _litDone.clear();
    ghosts?.clear();
    _wrongPitches.value = const {};
  }

  void _onNote(PlayedNote note) {
    // Uma conversão só, no topo: daqui para baixo tudo é altura escrita.
    final pitch = writtenFromReceived(note.pitch);
    final wait = _wait;
    if (note.on) {
      if (wait != null) {
        wait.noteOn(
          pitch,
          atMs: note.atSeconds * 1000 - inputLatencyMs,
          velocity: note.velocity,
        );
      } else {
        final musicalMs = scheduler.musicalAtDevice(
          note.atSeconds - inputLatencyMs / 1000,
        );
        _lastPlayedMusicalMs = musicalMs;
        _rt!.noteOn(pitch, musicalMs, velocity: note.velocity);
      }
    } else {
      wait?.noteOff(pitch);
      _releaseDone(pitch);
      ghosts?.release(pitch);
      if (_wrongPitches.value.contains(pitch)) {
        _wrongPitches.value = Set.of(_wrongPitches.value)..remove(pitch);
      }
    }
  }

  double _lastPlayedMusicalMs = 0;

  Map<String, double>? _onMsById;

  double _eventOnMs(String id) {
    final map = _onMsById ??= {for (final e in _track.events) e.id: e.onMs};
    return map[id] ?? 0;
  }

  Map<String, List<String>>? _tiedById;

  /// [id] e as continuações da ligadura dele: a cadeia acende inteira (é
  /// uma tecla só), na mesma cor.
  List<String> _chainOf(String id) {
    final map = _tiedById ??= {
      for (final e in _track.events)
        if (e.tied.isNotEmpty) e.id: e.tied,
    };
    final tied = map[id];
    return tied == null ? [id] : [id, ...tied];
  }

  /// O compasso (ocorrência) de um veredito no instante [ms]. Numa passagem
  /// única o instante é preso ao intervalo: uma tecla sem alvo apertada na
  /// folga depois do fim (ou antes do início) pertence ao último (primeiro)
  /// compasso do trecho, não ao vizinho de fora (U12).
  int _measureAt(double ms) {
    final range = this.range;
    if (range != null) {
      final last = range.endMs > range.startMs
          ? range.endMs - 1
          : range.startMs;
      ms = ms.clamp(range.startMs, last).toDouble();
    }
    return measureIndexAt?.call(ms) ?? 0;
  }

  void _record(NoteVerdict verdict) {
    final ms = verdict.eventId != null
        ? _eventOnMs(verdict.eventId!)
        : (_wait?.current.value?.onMs ?? _lastPlayedMusicalMs);
    final index = _measureAt(ms);
    _entries.add(ReportEntry(verdict, index, pass: passOf?.call(index) ?? 1));
    if (_wait == null) {
      _liveAdd(hit: verdict.kind == PracticeVerdictKind.correct);
    }
  }

  void _onVerdict(NoteVerdict verdict) {
    _record(verdict);
    if (verdict.kind == PracticeVerdictKind.wrong) _tally?.wrong();
    switch (verdict.kind) {
      case PracticeVerdictKind.correct:
        _unwatchShift(verdict);
        _correctCount.value++;
        if (_wait != null) {
          _closeHit(verdict.pitch);
        } else if (verdict.eventId != null) {
          controller.highlightAll(
            _chainOf(verdict.eventId!),
            color: correctColor,
            release: kPracticeCorrectRelease,
          );
        }
      case PracticeVerdictKind.wrong:
        _wrongCount.value++;
        _wrongPitches.value = Set.of(_wrongPitches.value)..add(verdict.pitch);
        ghosts?.press(verdict.pitch);
        // Modo espera com fantasma: a errada aparece só nela, enquanto a
        // tecla estiver apertada; as esperadas ficam como estão (pintar a
        // mais próxima de vermelho parecia dizer que ela é que está errada).
        _watchShift(verdict.pitch);
        final nearestId = _wait != null
            ? (ghosts == null ? _nearestExpectedId(verdict.pitch) : null)
            : _nearestEventId(verdict.pitch, _lastPlayedMusicalMs);
        if (nearestId != null) {
          controller.highlightAll(
            _chainOf(nearestId),
            color: wrongColor,
            attack: kPracticeWrongAttack,
            hold: kPracticeWrongHold,
            release: kPracticeWrongRelease,
          );
        }
      case PracticeVerdictKind.early:
      case PracticeVerdictKind.late:
        _unwatchShift(verdict);
        _correctCount.value++;
        if (verdict.eventId != null) {
          controller.highlightAll(
            _chainOf(verdict.eventId!),
            color: kPracticeOffBeatColor,
            release: kPracticeCorrectRelease,
          );
        }
      case PracticeVerdictKind.missed:
        if (verdict.eventId != null) {
          controller.highlightAll(
            _chainOf(verdict.eventId!),
            color: kPracticeMissedColor,
            attack: kPracticeWrongAttack,
            hold: kPracticeMissedHold,
            release: kPracticeWrongRelease,
          );
        }
    }
  }

  /// Q07: as notas esperadas perto de [ms] musicais: no modo espera, o acorde
  /// do passo; no tempo real, as da janela de 400 ms. Num acorde, a mais
  /// próxima de uma nota errada nem sempre é a que a pessoa queria tocar, por
  /// isso o detector recebe as distâncias a todas.
  Iterable<SoundEvent> _expectedNear(double ms) => _wait != null
      ? (_wait!.current.value?.notes ?? const <SoundEvent>[])
      : _track.startingIn(ms - 400, ms + 400, staves: hand.studentStaves);

  /// Q07: conta a nota errada [pitch] no detector de deslocamento.
  void _watchShift(int pitch) {
    final detector = shiftDetector;
    if (detector == null) return;
    final d = detector.wrong([
      for (final e in _expectedNear(_lastPlayedMusicalMs)) pitch - e.pitch,
    ]);
    if (d != null) onShift?.call(d);
  }

  /// Q07: o acerto de [verdict] zera a conta do detector (salvo se for um
  /// acaso do deslocamento, ver [ShiftDetector.correct]).
  void _unwatchShift(NoteVerdict verdict) {
    final detector = shiftDetector;
    if (detector == null) return;
    final id = verdict.eventId;
    detector.correct([
      if (id != null)
        for (final e in _expectedNear(_eventOnMs(id))) verdict.pitch - e.pitch,
    ]);
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
          _liveFromTally();
        }
        _finishRange();
        return;
      }
      _paintStep();
      if (_tallyStep == step.index) return;
      if (_tallyStep != null) {
        _tally?.stepDone();
        _liveFromTally();
      }
      _tally?.stepStarted(step.index, measureIndexAt?.call(step.onMs) ?? 0);
      _tallyStep = step.index;
      _setBrake(step.onMs);
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
    _paintStep();
    _setBrake(wait.current.value?.onMs);
    _syncGhostExpected();
  }

  // -------------------------------------------------------------------------
  // Cores do modo espera: três camadas por nota
  // -------------------------------------------------------------------------
  //
  // Embaixo, a cor da partitura. No meio, a de "esperada" nas notas do passo
  // pendente — cor fixa do `ScoreController` (`setColors`), que fica até o
  // passo fechar. Em cima, a de "certa" enquanto a tecla está apertada —
  // destaque animado, que ao apagar volta à cor fixa, então soltar uma nota
  // antes de o acorde fechar a devolve a "esperada". A errada vai para a
  // fantasma (ver [_onVerdict]). O player não acende as notas do aluno no
  // modo espera (`ScorePlayer.skipHighlight`, ligado pelo host).

  static const Duration _kForever = Duration(days: 365);

  /// Ids com a cor de "esperada" agora: as notas do passo pendente, com as
  /// continuações de ligadura.
  List<String> _expectedIds = const [];

  /// Índice do passo cujas cores estão na tela.
  int? _paintedStep;

  /// Notas certas apertadas do passo pendente, por tecla: acesas na cor de
  /// certa até a tecla soltar ou o acorde fechar.
  final Map<int, List<String>> _litStep = {};

  /// Notas de acordes já fechados ainda com a tecla apertada: continuam na
  /// cor de certa e apagam quando a tecla solta.
  final Map<int, List<String>> _litDone = {};

  /// Ids das notas do passo atual com a tecla [pitch], ligaduras inclusas
  /// (duas pautas podem ter a mesma tecla no mesmo instante).
  List<String> _stepIdsOf(PracticeStep step, int pitch) => [
    for (final e in step.notes)
      if (e.pitch == pitch) ..._chainOf(e.id),
  ];

  /// Põe na tela o passo publicado pela sessão: troca a camada do meio
  /// quando o passo muda e acende/apaga as certas conforme `remaining`.
  void _paintStep() {
    final step = _wait?.current.value;
    if (step?.index != _paintedStep) {
      // Passo novo: o que estava aceso do anterior sem ele fechar (loop,
      // salto) apaga; o que fechou já passou para [_litDone].
      for (final ids in _litStep.values) {
        _releaseIds(ids, Duration.zero);
      }
      _litStep.clear();
      _paintedStep = step?.index;
      _clearExpected();
      if (step != null) {
        _expectedIds = [for (final e in step.notes) ..._chainOf(e.id)];
        controller.setColors({for (final id in _expectedIds) id: pendingColor});
      }
    }
    if (step == null) return;
    for (final pitch in step.notes.map((e) => e.pitch).toSet()) {
      final hit = !step.remaining.contains(pitch);
      final lit = _litStep[pitch];
      if (hit && lit == null) {
        final ids = _stepIdsOf(step, pitch);
        controller.highlightAll(ids, color: correctColor, hold: _kForever);
        _litStep[pitch] = ids;
      } else if (!hit && lit != null) {
        // Soltou antes de o acorde fechar: volta a "esperada" na hora.
        _releaseIds(lit, Duration.zero);
        _litStep.remove(pitch);
      }
    }
  }

  /// O acorde fechou com [pitch] apertada: a nota fica na cor de certa até
  /// a tecla soltar ([_releaseDone]). Chamado antes de a sessão publicar o
  /// passo seguinte, com o passo que fechou ainda em `current`.
  void _closeHit(int pitch) {
    var ids = _litStep.remove(pitch);
    if (ids == null) {
      // A última nota do acorde: fechou sem republicar o passo.
      final step = _wait?.current.value;
      ids = step == null ? const <String>[] : _stepIdsOf(step, pitch);
      controller.highlightAll(ids, color: correctColor, hold: _kForever);
    }
    final previous = _litDone[pitch];
    if (previous != null) _releaseIds(previous, kPracticeCorrectRelease);
    _litDone[pitch] = ids;
  }

  /// Tecla [pitch] solta: a nota de acorde fechado que ela segurava apaga.
  void _releaseDone(int pitch) {
    final ids = _litDone.remove(pitch);
    if (ids != null) _releaseIds(ids, kPracticeCorrectRelease);
  }

  void _releaseIds(List<String> ids, Duration duration) {
    for (final id in ids) {
      controller.release(id, duration: duration);
    }
  }

  void _clearExpected() {
    for (final id in _expectedIds) {
      controller.clearColor(id);
    }
    _expectedIds = const [];
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
    _wait?.current.removeListener(_onStepChanged);
    _wait?.dispose();
    _rt?.dispose();
    _wrongPitches.dispose();
    _correctCount.dispose();
    _wrongCount.dispose();
  }
}

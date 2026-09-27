// T02: liga MidiInputService -> WaitModeSession (T01) -> cores do
// ScoreController + freio do ScoreAudioScheduler (K04) + teclado desenhado
// (M01). Ao contrário de practice_session.dart (T01, Dart puro), esta
// classe é Flutter-aware de propósito — é a cola entre hardware/UI e o
// núcleo puro.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart';

import '../audio/score_audio_scheduler.dart';
import '../midi/midi_input_service.dart';
import '../music/performance_track.dart';
import 'hand.dart';
import 'practice_colors.dart';
import 'practice_session.dart';

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
  }) : _midiInput = midiInput, // ignore: prefer_initializing_formals
       _session = WaitModeSession.forStaves(track, staves: hand.studentStaves) {
    _noteSub = _midiInput.notes.listen(_onNote);
    _verdictSub = _session.verdicts.listen(_onVerdict);
    _session.current.addListener(_onStepChanged);
  }

  final MidiInputService _midiInput;
  final ScoreAudioScheduler scheduler;
  final ScoreController controller;
  final Hand hand;
  final WaitModeSession _session;

  late final StreamSubscription<PlayedNote> _noteSub;
  late final StreamSubscription<NoteVerdict> _verdictSub;

  final ValueNotifier<Set<int>> _wrongPitches = ValueNotifier(const {});

  /// Passo pendente do aluno (para a UI mostrar progresso); `null` quando a
  /// sessão acabou.
  ValueListenable<PracticeStep?> get currentStep => _session.current;

  /// Pitches errados apertados agora — o teclado desenhado (M01) pinta em
  /// vermelho.
  ValueListenable<Set<int>> get wrongPitches => _wrongPitches;

  bool get done => _session.done;

  /// Arma o freio no primeiro passo, filtra o agendador para a mão do app
  /// (vazio em [Hand.ambas] — o app não toca nada) e começa do início.
  void start() {
    scheduler.setStaves(hand.appStaves);
    scheduler.setBrake(_session.current.value?.onMs);
    scheduler.play(0);
  }

  /// Solta o freio/filtro e para o agendador — volta ao comportamento
  /// normal de playback.
  void stop() {
    scheduler.setBrake(null);
    scheduler.setStaves(null);
    scheduler.pause();
    controller.releaseAll();
    _wrongPitches.value = const {};
  }

  void _onNote(PlayedNote note) {
    if (note.on) {
      _session.noteOn(
        note.pitch,
        atMs: note.atSeconds * 1000,
        velocity: note.velocity,
      );
    } else {
      _session.noteOff(note.pitch);
      if (_wrongPitches.value.contains(note.pitch)) {
        _wrongPitches.value = Set.of(_wrongPitches.value)..remove(note.pitch);
      }
    }
  }

  void _onVerdict(NoteVerdict verdict) {
    switch (verdict.kind) {
      case PracticeVerdictKind.correct:
        if (verdict.eventId != null) {
          controller.highlight(
            verdict.eventId!,
            color: kPracticeCorrectColor,
            release: kPracticeCorrectRelease,
          );
        }
      case PracticeVerdictKind.wrong:
        _wrongPitches.value = Set.of(_wrongPitches.value)..add(verdict.pitch);
        final nearestId = _nearestExpectedId(verdict.pitch);
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
      case PracticeVerdictKind.missed:
        break; // T03 (tempo real) — não emitidos pelo modo espera.
    }
  }

  /// Id da nota esperada mais próxima em pitch de [wrongPitch], entre as
  /// que ainda faltam no passo atual — a nota errada em si pode não existir
  /// na partitura.
  String? _nearestExpectedId(int wrongPitch) {
    final step = _session.current.value;
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
    scheduler.setBrake(_session.current.value?.onMs);
  }

  void dispose() {
    unawaited(_noteSub.cancel());
    unawaited(_verdictSub.cancel());
    _session.current.removeListener(_onStepChanged);
    _session.dispose();
    _wrongPitches.dispose();
  }
}

// T05: núcleo do treino de rítmica, Dart puro (como practice_session.dart):
// o aluno aperta qualquer tecla no instante de cada ataque; o pitch não
// importa. Sem relógio interno — quem chama converte o tempo tocado em ms
// musicais (mesma fórmula do T03) e chama [RhythmSession.tick].

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../music/performance_track.dart';

enum RhythmVerdictKind { correct, early, late, missed, extra }

/// Veredito de um ataque (onset). `extra` — toque sem alvo — não tem
/// [onsetIndex]/[onMs] e tem [eventIds] vazio.
@immutable
class RhythmVerdict {
  const RhythmVerdict({
    this.onsetIndex,
    this.onMs,
    this.eventIds = const [],
    required this.kind,
    this.deltaMs = 0,
    this.velocity = 0,
  });

  final int? onsetIndex;
  final double? onMs;

  /// Todas as notas do onset — a UI pinta o acorde inteiro.
  final List<String> eventIds;
  final RhythmVerdictKind kind;

  /// tocada − esperada, em ms musicais. `0` em `missed`/`extra`.
  final double deltaMs;
  final int velocity;

  @override
  String toString() =>
      'RhythmVerdict($kind #$onsetIndex Δ=${deltaMs.toStringAsFixed(1)}ms)';
}

/// Um ataque esperado: acordes de todas as pautas com o mesmo `onMs`.
@immutable
class RhythmOnset {
  const RhythmOnset({
    required this.index,
    required this.onMs,
    required this.notes,
  });

  final int index;
  final double onMs;
  final List<SoundEvent> notes;

  List<String> get eventIds => [for (final n in notes) n.id];
}

class RhythmSession {
  RhythmSession(
    this.onsets, {
    required this.speed,
    this.windowOkMs = 60,
    this.windowMaxMs = 130,
    this.chordDebounceMs = 45,
  }) {
    _pending = List.of(onsets);
  }

  /// Alvos = `onMs` distintos dos acordes das pautas do aluno, fundidos como
  /// em `WaitModeSession.forStaves`; ornamentos não contam (D-TREINO) e um
  /// onset só de ornamento some.
  factory RhythmSession.forStaves(
    PerformanceTrack track, {
    required Set<int> staves,
    required double speed,
    double windowOkMs = 60,
    double windowMaxMs = 130,
    double chordDebounceMs = 45,
  }) {
    final byOnMs = <double, List<SoundEvent>>{};
    for (final chord in track.chords(staves: staves)) {
      final notes = chord.notes.where((e) => !e.ornament).toList();
      if (notes.isEmpty) continue;
      byOnMs.putIfAbsent(chord.onMs, () => []).addAll(notes);
    }
    final keys = byOnMs.keys.toList()..sort();
    var i = 0;
    return RhythmSession(
      [
        for (final onMs in keys)
          RhythmOnset(index: i++, onMs: onMs, notes: byOnMs[onMs]!),
      ],
      speed: speed,
      windowOkMs: windowOkMs,
      windowMaxMs: windowMaxMs,
      chordDebounceMs: chordDebounceMs,
    );
  }

  final List<RhythmOnset> onsets;
  final double speed;
  final double windowOkMs;
  final double windowMaxMs;

  /// Toques a menos que isso (parede) do último que casou são o mesmo toque.
  final double chordDebounceMs;

  late List<RhythmOnset> _pending;
  double? _lastMatchWallMs;

  final StreamController<RhythmVerdict> _verdicts =
      StreamController<RhythmVerdict>.broadcast(sync: true);
  Stream<RhythmVerdict> get verdicts => _verdicts.stream;

  double get _okMs => windowOkMs * speed;
  double get _maxMs => windowMaxMs * speed;

  /// Tecla apertada, já em ms musicais. [atMs] é o carimbo de parede do
  /// toque (só para o debounce); se omitido, deriva de [musicalMs]/`speed`.
  void hit(double musicalMs, {double? atMs, int velocity = 0}) {
    final wall = atMs ?? musicalMs / speed;
    final last = _lastMatchWallMs;
    if (last != null && wall - last < chordDebounceMs && wall >= last) return;

    RhythmOnset? best;
    double bestDelta = 0;
    for (final o in _pending) {
      final delta = musicalMs - o.onMs;
      if (delta.abs() > _maxMs) continue;
      if (best == null || delta.abs() < bestDelta.abs()) {
        best = o;
        bestDelta = delta;
      }
    }

    if (best == null) {
      _verdicts.add(
        RhythmVerdict(kind: RhythmVerdictKind.extra, velocity: velocity),
      );
      return;
    }
    _pending.remove(best);
    _lastMatchWallMs = wall;
    _verdicts.add(
      RhythmVerdict(
        onsetIndex: best.index,
        onMs: best.onMs,
        eventIds: best.eventIds,
        kind: bestDelta.abs() <= _okMs
            ? RhythmVerdictKind.correct
            : (bestDelta < 0
                  ? RhythmVerdictKind.early
                  : RhythmVerdictKind.late),
        deltaMs: bestDelta,
        velocity: velocity,
      ),
    );
  }

  /// Duração (note-off) não é cobrada nesta etapa; existe para a opção
  /// "articulação" futura não mudar a API.
  void release(double musicalMs) {}

  /// Alvos cuja janela (`onMs + janelaMax`) passou sem toque viram `missed`.
  void tick(double musicalNowMs) {
    _pending.removeWhere((o) {
      if (musicalNowMs <= o.onMs + _maxMs) return false;
      _verdicts.add(
        RhythmVerdict(
          onsetIndex: o.index,
          onMs: o.onMs,
          eventIds: o.eventIds,
          kind: RhythmVerdictKind.missed,
        ),
      );
      return true;
    });
  }

  /// Loop A-B (T04): reinicia em `musicalMs`; [untilMs] (exclusivo) limita
  /// o fim do trecho.
  void resetTo(double musicalMs, {double? untilMs}) {
    _pending = onsets
        .where(
          (o) => o.onMs >= musicalMs && (untilMs == null || o.onMs < untilMs),
        )
        .toList();
    _lastMatchWallMs = null;
  }

  void dispose() => unawaited(_verdicts.close());
}

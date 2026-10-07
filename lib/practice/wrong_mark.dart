// Uma nota tocada errada no treino — de altura errada, ou da certa mas fora
// do tempo —, guardada para a revisão: qual tecla, em cima de que coluna da
// partitura e de que lado dela. Dart puro.
import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart' show GhostRequest;

import 'package:zywny_audio/performance_track.dart';

/// Até onde (ms musicais) uma nota errada ainda é posta ao lado do evento
/// mais próximo; além disso ela não tem de que lado ficar.
const double kWrongMarkReachMs = 1000;

/// Dentro de quanto (ms musicais) a nota conta como "no tempo" do evento:
/// cai em cima da coluna, sem lado.
const double kWrongMarkOnTimeMs = 1;

/// Nota tocada errada: a tecla ([pitch], na altura escrita), os eventos da
/// coluna onde ela é desenhada ([targetIds]) e o [side] — `-1` tocada antes
/// do tempo do evento (à esquerda), `1` depois (à direita), `0` sem noção de
/// tempo (modo espera) ou no tempo (em cima da coluna).
@immutable
class WrongMark {
  const WrongMark({
    required this.pitch,
    required this.targetIds,
    this.side = 0,
    this.measureIndex = 0,
    this.offBeat = false,
  });

  final int pitch;

  /// A tecla era a certa, mas foi tocada fora do tempo (adiantada ou
  /// atrasada); `false` é a altura errada.
  final bool offBeat;
  final List<String> targetIds;
  final int side;

  /// Compasso (ocorrência) da coluna, o mesmo do relatório.
  final int measureIndex;

  GhostRequest get ghostRequest =>
      GhostRequest(key: pitch, targetIds: targetIds, side: side);

  /// Tempo real: onde cai a nota errada tocada em [playedMs] (ms musicais)
  /// entre os eventos [events] (as pautas do aluno, sem ornamentos): a coluna
  /// do evento mais próximo no tempo — todos os do mesmo instante, que são o
  /// acorde — e o lado dela. `null` se não há evento ao alcance
  /// ([kWrongMarkReachMs]).
  static ({List<String> ids, double onMs, int side})? nearestColumn(
    Iterable<SoundEvent> events,
    double playedMs,
  ) {
    SoundEvent? nearest;
    var best = double.infinity;
    for (final e in events) {
      if (e.ornament) continue;
      final distance = (e.onMs - playedMs).abs();
      if (distance < best) {
        best = distance;
        nearest = e;
      }
    }
    if (nearest == null || best > kWrongMarkReachMs) return null;
    final onMs = nearest.onMs;
    return (
      ids: [
        for (final e in events)
          if (!e.ornament && (e.onMs - onMs).abs() < 0.5) e.id,
      ],
      onMs: onMs,
      side: (playedMs - onMs).abs() < kWrongMarkOnTimeMs
          ? 0
          : (playedMs < onMs ? -1 : 1),
    );
  }
}

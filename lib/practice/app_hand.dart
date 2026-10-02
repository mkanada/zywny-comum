import '../music/performance_track.dart';
import 'hand.dart';

/// Ids das notas das pautas que o **app** toca com a mão escolhida (U08), com
/// as continuações de ligadura (a cadeia acende junta). Vazio em
/// [Hand.ambas]: o app não toca nenhuma nota.
Set<String> appHandNoteIds(PerformanceTrack track, Hand hand) {
  final staves = hand.appStaves;
  if (staves.isEmpty) return const {};
  return {
    for (final e in track.events)
      if (staves.contains(e.staff)) ...[e.id, ...e.tied],
  };
}

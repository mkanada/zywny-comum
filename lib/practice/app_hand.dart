import '../music/performance_track.dart';
import 'hand.dart';

/// Ids das notas das pautas que o **app** toca com a mão escolhida (U08), com
/// as continuações de ligadura (a cadeia acende junta). Vazio em
/// [Hand.ambas]: o app não toca nenhuma nota.
Set<String> appHandNoteIds(PerformanceTrack track, Hand hand) =>
    _staffNoteIds(track, hand.appStaves);

/// Ids das notas das pautas que o **aluno** toca com a mão escolhida, com as
/// continuações de ligadura: no modo espera quem as pinta é o
/// `PracticeController`, não o player.
Set<String> studentHandNoteIds(PerformanceTrack track, Hand hand) =>
    _staffNoteIds(track, hand.studentStaves);

Set<String> _staffNoteIds(PerformanceTrack track, Set<int> staves) {
  if (staves.isEmpty) return const {};
  return {
    for (final e in track.events)
      if (staves.contains(e.staff)) ...[e.id, ...e.tied],
  };
}

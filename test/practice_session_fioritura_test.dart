// T11 do zywny-aprendizado: a *fioritura* (`SoundEvent.groupId`). Um grupo
// irregular longo tem a primeira e a última notas com a janela normal; as de
// dentro valem na ordem, com a janela do grupo todo. Sem `groupId`, a sessão é
// a de sempre.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/practice/practice_session.dart';

SoundEvent _ev(String id, int pitch, double onMs, {int? group}) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + 60,
  staff: 1,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
  groupId: group,
);

/// Onze notas subindo por grau conjunto (dó5 a fá6, em semitons), uma a cada
/// 100 ms desde 1000 ms: a nota 0 e a 10 são as pontas.
List<SoundEvent> _eleven({int? group = 1}) => [
  for (var i = 0; i < 11; i++)
    _ev('n$i', 72 + i, 1000.0 + i * 100, group: group),
];

List<NoteVerdict> _play(
  RealtimeSession session,
  List<(int, double)> presses, {
  double endMs = 10000,
}) {
  final verdicts = <NoteVerdict>[];
  session.verdicts.listen(verdicts.add);
  for (final (pitch, ms) in presses) {
    session.noteOn(pitch, ms);
    session.tick(ms);
  }
  session.tick(endMs);
  return verdicts;
}

int _count(List<NoteVerdict> v, PracticeVerdictKind kind) =>
    v.where((x) => x.kind == kind).length;

void main() {
  for (final adaptive in [false, true]) {
    group('fioritura (janela adaptativa: $adaptive)', () {
      RealtimeSession session(List<SoundEvent> events) =>
          RealtimeSession(events, speed: 1, adaptiveWindow: adaptive);

      test('as de dentro, na ordem e em rubato, são todas certas', () {
        // O rubato: as de dentro seguram a primeira e correm no fim.
        final presses = [
          (72, 1000.0),
          (73, 1130.0),
          (74, 1190.0),
          (75, 1260.0),
          (76, 1480.0),
          (77, 1500.0),
          (78, 1700.0),
          (79, 1740.0),
          (80, 1790.0),
          (81, 1850.0),
          (82, 2000.0),
        ];
        final verdicts = _play(session(_eleven()), presses);
        expect(verdicts.length, 11);
        expect(_count(verdicts, PracticeVerdictKind.correct), 11);
        expect(
          [for (final v in verdicts) v.eventId],
          [for (var i = 0; i < 11; i++) 'n$i'],
        );
      });

      test('fora de ordem dá erro', () {
        // A 4 vem antes da 3: a 3 fica para trás (missed) e, tocada depois,
        // não tem mais para onde ir (wrong).
        final presses = [
          (72, 1000.0),
          (73, 1100.0),
          (74, 1200.0),
          (76, 1300.0),
          (75, 1400.0),
          (77, 1500.0),
          (78, 1600.0),
          (79, 1700.0),
          (80, 1800.0),
          (81, 1900.0),
          (82, 2000.0),
        ];
        final verdicts = _play(session(_eleven()), presses);
        expect(_count(verdicts, PracticeVerdictKind.missed), 1);
        expect(_count(verdicts, PracticeVerdictKind.wrong), 1);
        expect(
          verdicts
              .firstWhere((v) => v.kind == PracticeVerdictKind.missed)
              .eventId,
          'n3',
        );
      });

      test('a última fora da janela normal dá atraso', () {
        final inOrder = [
          for (var i = 0; i < 10; i++) (72 + i, 1000.0 + i * 100),
        ];
        // A última, 110 ms depois: dentro dos 150, fora dos 75 de certo.
        final verdicts = _play(session(_eleven()), [...inOrder, (82, 2110.0)]);
        expect(verdicts.last.eventId, 'n10');
        expect(verdicts.last.kind, PracticeVerdictKind.late);
        expect(_count(verdicts, PracticeVerdictKind.correct), 10);
      });

      test('a última além dos 150 ms é perdida; a de dentro some no fim', () {
        // Parou na 6: as de dentro de 7 a 9 ficam para trás quando a janela
        // do grupo fecha.
        final presses = [
          for (var i = 0; i <= 6; i++) (72 + i, 1000.0 + i * 100),
        ];
        final verdicts = _play(session(_eleven()), presses);
        expect(_count(verdicts, PracticeVerdictKind.correct), 7);
        expect(_count(verdicts, PracticeVerdictKind.missed), 4);
      });

      test('sem groupId, tudo é como antes', () {
        // O mesmo rubato do primeiro caso, sem grupo: as janelas de 150 ms
        // de cada nota perdem e erram as que fogem delas.
        final presses = [
          (72, 1000.0),
          (73, 1130.0),
          (74, 1190.0),
          (75, 1260.0),
          (76, 1480.0),
          (77, 1500.0),
          (78, 1700.0),
          (79, 1740.0),
          (80, 1790.0),
          (81, 1850.0),
          (82, 2000.0),
        ];
        final plain = _play(session(_eleven(group: null)), presses);
        final grouped = _play(session(_eleven()), presses);
        expect(_count(grouped, PracticeVerdictKind.correct), 11);
        expect(_count(plain, PracticeVerdictKind.correct), lessThan(11));
        expect(
          _count(plain, PracticeVerdictKind.missed) +
              _count(plain, PracticeVerdictKind.wrong) +
              _count(plain, PracticeVerdictKind.late) +
              _count(plain, PracticeVerdictKind.early),
          greaterThan(0),
        );
      });
    });
  }

  group('PerformanceTrack.withOrnaments(groups)', () {
    test('põe o groupId nos eventos pelo id', () {
      final track = PerformanceTrack.fromEvents(_eleven(group: null));
      final out = track.withOrnaments(
        groups: {for (var i = 0; i < 11; i++) 'n$i': 7},
      );
      expect(out.events.every((e) => e.groupId == 7), isTrue);
      expect(track.events.every((e) => e.groupId == null), isTrue);
    });

    test('sem grupos, devolve a própria track', () {
      final track = PerformanceTrack.fromEvents(_eleven(group: null));
      expect(identical(track.withOrnaments(), track), isTrue);
    });
  });
}

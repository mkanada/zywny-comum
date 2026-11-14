// ND01 (docs/plano/ND00 e ND01): a sessão do modo espera que segura a nota.
// Com `holdFraction`, o passo só fecha quando o relógio musical passa do fim
// da cápsula com as notas do passo ainda presas. Sem `holdFraction`, nada muda.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/practice/practice_session.dart';

SoundEvent _note(String id, int pitch, double onMs, double offMs) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: offMs,
  staff: 1,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
);

PracticeStep _step(int index, double onMs, List<SoundEvent> notes) =>
    PracticeStep(
      index: index,
      onMs: onMs,
      notes: notes,
      remaining: notes.map((e) => e.pitch).toSet(),
    );

void main() {
  group('WaitModeSession com holdFraction (notas com duração)', () {
    test('sem holdFraction, o passo fecha no aperto', () {
      final session = WaitModeSession([
        _step(0, 0, [_note('c', 60, 0, 1000)]),
      ]);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(60, atMs: 0);

      expect(session.done, isTrue);
      expect(verdicts.single.kind, PracticeVerdictKind.correct);
      expect(session.current.value, isNull);
    });

    test(
      'semínima de 0 a 1000: a cápsula vai de 0 a 800 e só fecha depois',
      () {
        final session = WaitModeSession([
          _step(0, 0, [_note('c', 60, 0, 1000)]),
          _step(1, 1000, [_note('d', 62, 1000, 1500)]),
        ], holdFraction: 0.8);
        final verdicts = <NoteVerdict>[];
        session.verdicts.listen(verdicts.add);

        session.noteOn(60, atMs: 0);
        expect(session.current.value!.holdStartMs, 0);
        expect(session.current.value!.holdEndMs, 800);

        session.tick(799);
        expect(session.done, isFalse);
        expect(verdicts, isEmpty);

        session.tick(800);
        expect(verdicts.single.kind, PracticeVerdictKind.correct);
        expect(session.current.value!.index, 1);
        expect(session.current.value!.holdEndMs, isNull);
        expect(session.current.value!.holdStartMs, isNull);
      },
    );

    test('soltar em tick(500) é soltura cedo: sem veredito, a nota volta', () {
      final session = WaitModeSession([
        _step(0, 0, [_note('c', 60, 0, 1000)]),
      ], holdFraction: 0.8);
      final verdicts = <NoteVerdict>[];
      final releases = <HoldRelease>[];
      session.verdicts.listen(verdicts.add);
      session.releases.listen(releases.add);

      session.noteOn(60, atMs: 0);
      session.tick(500);
      session.noteOff(60);

      expect(releases, hasLength(1));
      expect(releases.single.stepIndex, 0);
      expect(releases.single.pitch, 60);
      expect(releases.single.onMs, 0);
      expect(releases.single.atMs, 500);
      expect(releases.single.fraction, closeTo(0.625, 1e-9));
      expect(verdicts, isEmpty);
      expect(session.current.value!.remaining, {60});
      expect(session.current.value!.holdEndMs, isNull);

      // Apertar de novo arma a cápsula outra vez.
      session.noteOn(60, atMs: 600);
      expect(session.current.value!.holdEndMs, 800);
      session.tick(800);
      expect(session.done, isTrue);
      expect(verdicts.single.kind, PracticeVerdictKind.correct);
    });

    test('acorde com offMs 1000 e 2000: a cápsula usa a nota mais curta', () {
      final session = WaitModeSession([
        _step(0, 0, [_note('c', 60, 0, 1000), _note('e', 64, 0, 2000)]),
      ], holdFraction: 0.8);

      session.noteOn(60, atMs: 0);
      session.noteOn(64, atMs: 10);

      expect(session.current.value!.holdEndMs, 800);
    });

    test(
      'nota de 0 a 2000 com o passo seguinte em 1000: a cápsula para em 800',
      () {
        final session = WaitModeSession([
          _step(0, 0, [_note('c', 60, 0, 2000)]),
          _step(1, 1000, [_note('d', 62, 1000, 1500)]),
        ], holdFraction: 0.8);

        session.noteOn(60, atMs: 0);

        expect(session.current.value!.holdEndMs, 800);
      },
    );

    test(
      'tecla errada no meio da cápsula: não fecha no tempo, só ao soltá-la',
      () {
        final session = WaitModeSession([
          _step(0, 0, [_note('c', 60, 0, 1000)]),
        ], holdFraction: 0.8);
        final verdicts = <NoteVerdict>[];
        session.verdicts.listen(verdicts.add);

        session.noteOn(60, atMs: 0);
        session.noteOn(61, atMs: 10);
        expect(verdicts.single.kind, PracticeVerdictKind.wrong);

        session.tick(800);
        expect(session.done, isFalse);

        session.noteOff(61);
        expect(session.done, isTrue);
        expect(verdicts.map((v) => v.kind), [
          PracticeVerdictKind.wrong,
          PracticeVerdictKind.correct,
        ]);
      },
    );

    test('tick já além do fim antes do aperto: o aperto fecha na hora', () {
      final session = WaitModeSession([
        _step(0, 0, [_note('c', 60, 0, 1000)]),
        _step(1, 1000, [_note('d', 62, 1000, 1500)]),
      ], holdFraction: 0.8);

      session.tick(900);
      expect(session.done, isFalse);

      session.noteOn(60, atMs: 0);
      expect(session.current.value!.index, 1);
      expect(session.current.value!.holdEndMs, isNull);
    });

    test('resetTo no meio da cápsula: o passo volta sem cápsula', () {
      final session = WaitModeSession([
        _step(0, 0, [_note('c', 60, 0, 1000)]),
        _step(1, 1000, [_note('d', 62, 1000, 1500)]),
      ], holdFraction: 0.8);

      session.noteOn(60, atMs: 0);
      session.tick(500);
      expect(session.current.value!.holdEndMs, 800);

      session.resetTo(0);
      expect(session.current.value!.index, 0);
      expect(session.current.value!.holdEndMs, isNull);
      expect(session.current.value!.holdStartMs, isNull);
      expect(session.current.value!.remaining, {60});
    });
  });
}

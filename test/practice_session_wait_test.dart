// T01, modo espera (docs/plano/T01-casador-de-notas.md). O casador em si
// é testado com passos sintéticos (controle total sobre acordes/tempos);
// `WaitModeSession.forStaves` (fusão de pautas via N03) usa o corpus real,
// como os outros testes de `PerformanceTrack`.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/practice/practice_session.dart';

PerformanceTrack _loadTrack(String fixture) {
  final bytes = File('test/fixtures/$fixture').readAsBytesSync();
  return PerformanceTrack.fromDocument(
    VsbDocument.fromBytes(Uint8List.fromList(bytes)),
  );
}

SoundEvent _ev(String id, int pitch, double onMs, {int staff = 1}) =>
    SoundEvent(
      id: id,
      pitch: pitch,
      onMs: onMs,
      offMs: onMs + 400,
      staff: staff,
      channel: 0,
      program: 0,
      velocity: 80,
      ornament: false,
    );

void main() {
  group('WaitModeSession', () {
    test(
      'acorde de 3 notas tocado em qualquer ordem dentro de 300ms avança',
      () {
        final steps = [
          PracticeStep(
            index: 0,
            onMs: 0,
            notes: [_ev('c', 60, 0), _ev('e', 64, 0), _ev('g', 67, 0)],
            remaining: {60, 64, 67},
          ),
        ];
        final session = WaitModeSession(steps);
        final verdicts = <NoteVerdict>[];
        session.verdicts.listen(verdicts.add);

        session.noteOn(64, atMs: 0);
        session.noteOn(60, atMs: 120);
        session.noteOn(67, atMs: 260); // última, dentro dos 300ms

        expect(session.done, isTrue);
        expect(
          verdicts.where((v) => v.kind == PracticeVerdictKind.wrong).length,
          0,
        );
        expect(
          verdicts.where((v) => v.kind == PracticeVerdictKind.correct).length,
          3,
        );
      },
    );

    test('nota errada no meio do acorde recomeça a tentativa: precisa soltar '
        'e tocar o acorde inteiro de novo', () {
      final session = WaitModeSession([
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0)],
          remaining: {60, 64},
        ),
      ]);
      session.noteOn(60, atMs: 0);
      session.noteOn(72, atMs: 50); // errada
      session.noteOn(64, atMs: 100); // com a 60 ainda presa: não fecha
      expect(session.done, isFalse);
      expect(session.current.value!.remaining, {60});
      session.noteOff(60);
      session.noteOff(72);
      session.noteOn(60, atMs: 200); // 64 segurada + 60 de novo
      expect(session.done, isTrue);
    });

    test('soltar uma nota antes de o acorde fechar a faz faltar de novo', () {
      final session = WaitModeSession([
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0)],
          remaining: {60, 64},
        ),
      ]);
      session.noteOn(60, atMs: 0);
      session.noteOff(60);
      session.noteOn(64, atMs: 100);
      expect(session.done, isFalse);
      expect(session.current.value!.remaining, {60});
      session.noteOn(60, atMs: 150);
      expect(session.done, isTrue);
    });

    test('remaining encolhe a cada nota certa, sem avançar o passo', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0)],
          remaining: {60, 64},
        ),
      ];
      final session = WaitModeSession(steps);

      expect(session.current.value!.remaining, {60, 64});
      session.noteOn(60, atMs: 0);
      expect(session.current.value!.index, 0, reason: 'ainda no passo 0');
      expect(session.current.value!.remaining, {64});
      session.noteOn(64, atMs: 10);
      expect(session.done, isTrue);
    });

    test('nota repetida entre passos exige soltar e apertar de novo '
        '(tecla segurada não avança)', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('a', 60, 0)],
          remaining: {60},
        ),
        PracticeStep(
          index: 1,
          onMs: 500,
          notes: [_ev('b', 60, 500)],
          remaining: {60},
        ),
      ];
      final session = WaitModeSession(steps);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(60, atMs: 0);
      expect(session.current.value!.index, 1);

      // Tecla continua fisicamente apertada: tentar de novo sem soltar
      // antes não pode contar como a nota do passo 1.
      session.noteOn(60, atMs: 10);
      expect(session.current.value!.index, 1);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct).length,
        1,
      );

      session.noteOff(60);
      session.noteOn(60, atMs: 600);
      expect(session.done, isTrue);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct).length,
        2,
      );
    });

    test('forStaves funde acordes das duas pautas com o mesmo onMs num só '
        'passo (Maple Leaf Rag)', () {
      final track = _loadTrack('maple-leaf-rag.vsb');
      final session = WaitModeSession.forStaves(track, staves: {1, 2});

      // Do teste de N03 (performance_track_test.dart): a pauta 2 sozinha
      // já tem acordes em onMs 0 e 600. Se a pauta 1 também soar nesses
      // instantes, o passo correspondente precisa trazer as notas das
      // duas juntas.
      final byOnMs = <double, PracticeStep>{};
      var step = session.current.value;
      var i = 0;
      while (step != null && i < 10000) {
        byOnMs[step.onMs] = step;
        // Toca e solta tudo do passo (staccato) para andar até o fim sem
        // travar em nota repetida — só para inspecionar os passos
        // visitados, o teste de nota repetida é o de cima.
        final pitches = step.remaining.toList();
        for (final pitch in pitches) {
          session.noteOn(pitch, atMs: i.toDouble());
        }
        for (final pitch in pitches) {
          session.noteOff(pitch);
        }
        step = session.current.value;
        i++;
      }

      final at0 = byOnMs[0]!;
      expect(at0.notes.where((e) => e.staff == 2).map((e) => e.pitch).toSet(), {
        39,
        51,
      });
      expect(session.done, isTrue);
    });

    test('resetTo volta para o primeiro passo com onMs >= ponto pedido', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('a', 60, 0)],
          remaining: {60},
        ),
        PracticeStep(
          index: 1,
          onMs: 1000,
          notes: [_ev('b', 62, 1000)],
          remaining: {62},
        ),
        PracticeStep(
          index: 2,
          onMs: 2000,
          notes: [_ev('c', 64, 2000)],
          remaining: {64},
        ),
      ];
      final session = WaitModeSession(steps);
      session.noteOn(60, atMs: 0);
      expect(session.current.value!.index, 1);

      session.resetTo(1500);
      expect(session.current.value!.index, 2);

      session.resetTo(0);
      expect(session.current.value!.index, 0);
    });

    test('acorde pingado sem segurar não acumula: fora da janela a '
        'tentativa recomeça', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0), _ev('g', 67, 0)],
          remaining: {60, 64, 67},
        ),
      ];
      final session = WaitModeSession(steps);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(60, atMs: 0);
      session.noteOff(60);
      // 500ms depois, sem nada segurado: recomeça do zero, o 64 vira o
      // primeiro da nova tentativa.
      session.noteOn(64, atMs: 500);
      expect(session.done, isFalse);
      expect(session.current.value!.remaining, {60, 67});
      session.noteOff(64);
      session.noteOn(67, atMs: 1100);
      expect(session.done, isFalse);
      expect(session.current.value!.remaining, {60, 64});
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.correct).length,
        3,
      );
    });

    test('nota segurada através da janela continua valendo: o que soa '
        'junto avança', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0), _ev('g', 67, 0)],
          remaining: {60, 64, 67},
        ),
      ];
      final session = WaitModeSession(steps);

      session.noteOn(60, atMs: 0); // segura
      session.noteOn(64, atMs: 500); // fora da janela: recomeça, 60 vale
      expect(session.current.value!.remaining, {67});
      session.noteOn(67, atMs: 550);
      expect(session.done, isTrue);
    });

    test('na fronteira da janela (300ms) ainda vale, além não', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0)],
          remaining: {60, 64},
        ),
      ];
      final session = WaitModeSession(steps);

      session.noteOn(60, atMs: 0);
      session.noteOn(64, atMs: 300);
      expect(session.done, isTrue);
    });

    test('errada fora da janela recomeça a tentativa sem abrir janela', () {
      final steps = [
        PracticeStep(
          index: 0,
          onMs: 0,
          notes: [_ev('c', 60, 0), _ev('e', 64, 0), _ev('g', 67, 0)],
          remaining: {60, 64, 67},
        ),
      ];
      final session = WaitModeSession(steps);
      final verdicts = <NoteVerdict>[];
      session.verdicts.listen(verdicts.add);

      session.noteOn(60, atMs: 0);
      session.noteOff(60);
      session.noteOn(72, atMs: 500); // errada, fora da janela: recomeça
      expect(session.current.value!.remaining, {60, 64, 67});
      session.noteOn(60, atMs: 550);
      session.noteOn(64, atMs: 600);
      session.noteOn(67, atMs: 650);
      expect(session.done, isTrue);
      expect(
        verdicts.where((v) => v.kind == PracticeVerdictKind.wrong).length,
        1,
      );
    });
  });
}

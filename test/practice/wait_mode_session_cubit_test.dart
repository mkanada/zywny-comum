// BL28: a sessão de espera é um Cubit do passo atual. Os testes conferem as
// transições (o que o `stream` entrega) e o aviso síncrono do motor
// (`onStepChanged`), que tem de vir na mesma pilha da mudança e antes de
// qualquer `await`.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/practice/practice_session.dart';

SoundEvent _ev(String id, int pitch, double onMs) => SoundEvent(
  id: id,
  pitch: pitch,
  onMs: onMs,
  offMs: onMs + 400,
  staff: 1,
  channel: 0,
  program: 0,
  velocity: 80,
  ornament: false,
);

/// Dois passos de uma nota cada: o 0 (dó) e o 1 (ré).
List<PracticeStep> _dois() => [
  PracticeStep(index: 0, onMs: 0, notes: [_ev('a', 60, 0)], remaining: {60}),
  PracticeStep(
    index: 1,
    onMs: 500,
    notes: [_ev('b', 62, 500)],
    remaining: {62},
  ),
];

/// Um passo de acorde (dó e mi juntos), para ver o estado publicado com a
/// nota que falta.
List<PracticeStep> _acorde() => [
  PracticeStep(
    index: 0,
    onMs: 0,
    notes: [_ev('a', 60, 0), _ev('c', 64, 0)],
    remaining: {60, 64},
  ),
];

void main() {
  _transicoes();
  _avisoSincrono();
}

void _transicoes() {
  group('WaitModeSession (Cubit do passo atual)', () {
    blocTest<WaitModeSession, PracticeStep?>(
      'a nota certa fecha o passo 0 e publica o 1',
      build: () => WaitModeSession(_dois()),
      act: (s) => s.noteOn(60, atMs: 0),
      expect: () => [isA<PracticeStep>().having((p) => p.index, 'index', 1)],
    );

    blocTest<WaitModeSession, PracticeStep?>(
      'uma tecla errada não muda o passo (só o veredito)',
      build: () => WaitModeSession(_dois()),
      act: (s) => s.noteOn(61, atMs: 0),
      expect: () => const <Object>[],
    );

    blocTest<WaitModeSession, PracticeStep?>(
      'a nota certa de um acorde publica o que falta, e soltá-la devolve',
      build: () => WaitModeSession(_acorde()),
      act: (s) {
        s.noteOn(60, atMs: 0);
        s.noteOff(60);
      },
      expect: () => [
        isA<PracticeStep>().having((p) => p.remaining, 'faltam', {64}),
        isA<PracticeStep>().having((p) => p.remaining, 'faltam', {60, 64}),
      ],
    );

    blocTest<WaitModeSession, PracticeStep?>(
      'acabada a peça, o estado é null e não avisa de novo',
      build: () => WaitModeSession(_dois()),
      act: (s) {
        s.noteOn(60, atMs: 0);
        s.noteOn(62, atMs: 500);
        s.noteOn(62, atMs: 600);
      },
      expect: () => [
        isA<PracticeStep>().having((p) => p.index, 'index', 1),
        isNull,
      ],
    );
  });
}

void _avisoSincrono() {
  group('WaitModeSession.onStepChanged (aviso síncrono do motor)', () {
    test('chega na mesma pilha da mudança, antes de qualquer await', () {
      final session = WaitModeSession(_dois());
      final vistos = <int?>[];
      session.onStepChanged = () => vistos.add(session.state?.index);

      session.noteOn(60, atMs: 0);

      expect(vistos, [1], reason: 'o aviso é síncrono: já aconteceu aqui');
      unawaited(session.close());
    });

    test('não avisa ao criar a sessão nem quando o passo não muda', () {
      final session = WaitModeSession(_dois());
      var avisos = 0;
      session.onStepChanged = () => avisos++;

      session.noteOn(61, atMs: 0); // errada: o passo não muda
      expect(avisos, 0);
      session.noteOff(61); // soltar a errada não avisa
      expect(avisos, 0);

      session.noteOn(60, atMs: 0);
      session.noteOn(62, atMs: 500);
      final depois = avisos;
      expect(session.state, isNull);

      // Peça acabada: `null` sobre `null` não avisa mais.
      session.noteOn(62, atMs: 600);
      expect(avisos, depois);
      unawaited(session.close());
    });

    test('close fecha o estado e não aceita mais o aviso', () async {
      final session = WaitModeSession(_dois());
      await session.close();
      expect(session.isClosed, isTrue);
    });
  });
}

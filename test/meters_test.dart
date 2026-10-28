// EX07: os nove medidores (lib/practice/meters.dart), cada um com uma
// gravação montada à mão (sem MIDI). Os números são os da tabela do EX07.

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_comum/practice/expression_marks.dart';
import 'package:zywny_comum/practice/meters.dart';
import 'package:zywny_comum/practice/performance_capture.dart';
import 'package:zywny_comum/practice/practice_report.dart';
import 'package:zywny_comum/practice/practice_session.dart';

/// Uma partitura e o que o aluno tocou dela, em ms musicais.
class _Scene {
  final _written = <SoundEvent>[];
  final capture = PerformanceCapture();
  final _pairs = <({SoundEvent written, int index})>[];

  /// Uma nota escrita de [on] a [off], na pauta [staff].
  SoundEvent note(
    String id,
    int pitch,
    double on,
    double off, {
    int staff = 1,
  }) {
    final event = SoundEvent(
      id: id,
      pitch: pitch,
      onMs: on,
      offMs: off,
      staff: staff,
      channel: 0,
      program: 0,
      velocity: 80,
      ornament: false,
    );
    _written.add(event);
    return event;
  }

  /// O aluno toca [event]: a tecla vai de [on] a [off] (o padrão é a hora
  /// escrita); sem [off], fica presa.
  void play(SoundEvent event, {double? on, double? off, int velocity = 80}) {
    final index = capture.noteOn(event.pitch, velocity, on ?? event.onMs);
    if (off != null) capture.noteOff(event.pitch, off);
    _pairs.add((written: event, index: index));
  }

  MeterInput input({
    ExpressionMarks marks = ExpressionMarks.empty,
    double speed = 1,
    bool legato = false,
    bool pedal = false,
    List<double> changes = const [],
    List<double> beats = const [],
    PracticeReport? report,
    List<int> chorusStarts = const [],
    bool roundDone = false,
  }) => MeterInput(
    track: PerformanceTrack.fromEvents(_written),
    staves: {1, 2},
    capture: capture,
    matches: [
      for (final p in _pairs)
        MatchedNote(written: p.written, played: capture.noteAt(p.index)),
    ],
    marks: marks,
    speed: speed,
    measureAt: (ms) => (ms / 1000).floor(),
    legatoRequested: legato,
    pedalRequested: pedal,
    harmonyChangesMs: changes,
    beatsMs: beats,
    report: report,
    chorusStarts: chorusStarts,
    roundDone: roundDone,
  );
}

/// Quatro semínimas seguidas a 120 bpm (500 ms), alturas 60 a 63.
List<SoundEvent> _quarters(_Scene s) => [
  for (var i = 0; i < 4; i++) s.note('n$i', 60 + i, i * 500.0, i * 500.0 + 500),
];

void main() {
  group('legato', () {
    test('ligações sem buraco nem borrão passam: 100%', () {
      final s = _Scene();
      final n = _quarters(s);
      for (var i = 0; i < 4; i++) {
        s.play(n[i], off: i < 3 ? n[i + 1].onMs + 10 : n[i].offMs);
      }

      final r = meterLegato(s.input(legato: true), target: 85);

      expect(r.value, 100);
      expect(r.passed, isTrue);
      expect(r.sentence, '3 de 3 ligações limpas.');
    });

    test('um buraco de 50 ms tira uma ligação e a frase cita o compasso', () {
      final s = _Scene();
      final n = _quarters(s);
      s.play(n[0], off: 510);
      s.play(n[1], off: 950);
      s.play(n[2], off: 1510);
      s.play(n[3], off: 2000);

      final r = meterLegato(s.input(legato: true), target: 85);

      expect(r.value, closeTo(66.67, 0.01));
      expect(r.passed, isFalse);
      expect(r.sentence, '2 de 3 ligações limpas; 1 com buraco (c. 2).');
      expect(r.measures, [1]);
    });

    test('uma sobreposição de 200 ms é borrão e a frase cita o compasso', () {
      final s = _Scene();
      final n = _quarters(s);
      s.play(n[0], off: 700);
      s.play(n[1], off: 1010);
      s.play(n[2], off: 1510);
      s.play(n[3], off: 2000);

      final r = meterLegato(s.input(legato: true));

      expect(r.value, closeTo(66.67, 0.01));
      expect(r.sentence, '2 de 3 ligações limpas; 1 borradas (c. 1).');
    });

    test('sem ligadura escrita e sem pedido de legato, não há o que medir', () {
      final s = _Scene();
      final n = _quarters(s);
      for (final e in n) {
        s.play(e);
      }

      final r = meterLegato(s.input());

      expect(r.value.isNaN, isTrue);
      expect(r.passed, isNull);
      expect(r.sentence, 'nada para medir aqui');
    });

    test('a ligadura de expressão vale mesmo sem o pedido de legato', () {
      final s = _Scene();
      final n = _quarters(s);
      s.play(n[0], off: 510);
      s.play(n[1], off: 500);

      final r = meterLegato(
        s.input(marks: const ExpressionMarks(slurs: [('n0', 'n1')])),
      );

      expect(r.value, 100);
    });
  });

  group('staccato', () {
    test('semínima de 1000 ms tocada com 200 ms passa; com 800 ms, não', () {
      const marks = ExpressionMarks(staccato: {'a'});

      final curta = _Scene();
      curta.play(curta.note('a', 60, 0, 1000), off: 200);
      final passa = meterStaccato(curta.input(marks: marks), target: 50);

      final longa = _Scene();
      longa.play(longa.note('a', 60, 0, 1000), off: 800);
      final falha = meterStaccato(longa.input(marks: marks), target: 50);

      expect(passa.value, 100);
      expect(passa.passed, isTrue);
      expect(falha.value, 0);
      expect(falha.passed, isFalse);
      expect(
        falha.sentence,
        '0 de 1 staccatos soaram curtos; 1 soaram longos '
        '(c. 1).',
      );
    });

    test('sem marcas de staccato, nada para medir', () {
      final s = _Scene();
      s.play(s.note('a', 60, 0, 1000), off: 200);

      final r = meterStaccato(s.input());

      expect(r.value.isNaN, isTrue);
      expect(r.sentence, 'nada para medir aqui');
    });
  });

  group('dynamics', () {
    const marks = ExpressionMarks(
      dynamics: [
        DynamicMark(atMs: 0, level: DynamicLevel.p),
        DynamicMark(atMs: 1000, level: DynamicLevel.f),
      ],
    );

    _Scene pianoThenForte(int piano, int forte) {
      final s = _Scene();
      s.play(s.note('a', 60, 0, 500), velocity: piano);
      s.play(s.note('b', 60, 500, 1000), velocity: piano);
      s.play(s.note('c', 60, 1000, 1500), velocity: forte);
      s.play(s.note('d', 60, 1500, 2000), velocity: forte);
      return s;
    }

    test('um trecho p a 40 e um f a 90 passam', () {
      final r = meterDynamics(
        pianoThenForte(40, 90).input(marks: marks),
        target: 100,
      );

      expect(r.value, 100);
      expect(r.passed, isTrue);
    });

    test('p a 70 e f a 75 não passam: a diferença é menor que 12', () {
      final r = meterDynamics(
        pianoThenForte(70, 75).input(marks: marks),
        target: 100,
      );

      expect(r.value, 0);
      expect(r.passed, isFalse);
      expect(r.measures, [1]);
    });

    test('velocities todas iguais dão o aviso do teclado, sem reprovar', () {
      final r = meterDynamics(
        pianoThenForte(80, 80).input(marks: marks),
        target: 100,
      );

      expect(r.value.isNaN, isTrue);
      expect(r.passed, isNull);
      expect(r.sentence, 'seu teclado não manda a força da tecla');
    });

    test('o crescendo sobe a velocity: a inclinação tem o sinal certo', () {
      final s = _Scene();
      s.play(s.note('a', 60, 0, 500), velocity: 60);
      s.play(s.note('b', 60, 2000, 2300), velocity: 40);
      s.play(s.note('c', 60, 2333, 2600), velocity: 55);
      s.play(s.note('d', 60, 2666, 2900), velocity: 70);
      s.play(s.note('e', 60, 2999, 3200), velocity: 85);

      final r = meterDynamics(
        s.input(
          marks: const ExpressionMarks(
            dynamics: [DynamicMark(atMs: 0, level: DynamicLevel.p)],
            wedges: [WedgeMark(startMs: 2000, endMs: 3000, crescendo: true)],
          ),
        ),
        target: 100,
      );

      expect(r.value, 100);
    });

    test('o diminuendo que sobe a velocity está errado', () {
      final s = _Scene();
      s.play(s.note('a', 60, 0, 500), velocity: 60);
      s.play(s.note('b', 60, 2000, 2300), velocity: 40);
      s.play(s.note('c', 60, 2333, 2600), velocity: 55);
      s.play(s.note('d', 60, 2666, 2900), velocity: 70);
      s.play(s.note('e', 60, 2999, 3200), velocity: 85);

      final r = meterDynamics(
        s.input(
          marks: const ExpressionMarks(
            dynamics: [DynamicMark(atMs: 0, level: DynamicLevel.p)],
            wedges: [WedgeMark(startMs: 2000, endMs: 3000, crescendo: false)],
          ),
        ),
        target: 100,
      );

      expect(r.value, 0);
    });
  });

  group('balance', () {
    test('melodia a 90 e acompanhamento a 60 dão 30', () {
      final s = _Scene();
      s.play(s.note('m', 72, 0, 500, staff: 1), velocity: 90);
      s.play(s.note('b', 48, 0, 500, staff: 2), velocity: 60);

      final r = meterBalance(s.input(), target: 10);

      expect(r.value, 30);
      expect(r.passed, isTrue);
      expect(
        r.sentence,
        'a melodia sai 30 de força acima do acompanhamento '
        '(alvo 10).',
      );
    });

    test('num acorde de uma pauta só, a nota mais aguda é a melodia', () {
      final s = _Scene();
      s.play(s.note('alta', 72, 0, 500), velocity: 90);
      s.play(s.note('baixa', 60, 0, 500), velocity: 60);

      final r = meterBalance(s.input());

      expect(r.value, 30);
    });

    test('o acompanhamento mais forte aparece com sinal de quem manda', () {
      final s = _Scene();
      s.play(s.note('m', 72, 0, 500, staff: 1), velocity: 60);
      s.play(s.note('b', 48, 0, 500, staff: 2), velocity: 90);

      final r = meterBalance(s.input(), target: 10);

      expect(r.value, -30);
      expect(r.passed, isFalse);
      expect(
        r.sentence,
        'o acompanhamento sai 30 acima da melodia (alvo 10) (c. 1).',
      );
    });

    test('velocities iguais dão o aviso do teclado', () {
      final s = _Scene();
      s.play(s.note('m', 72, 0, 500, staff: 1));
      s.play(s.note('b', 48, 0, 500, staff: 2));

      final r = meterBalance(s.input());

      expect(r.value.isNaN, isTrue);
      expect(r.sentence, 'seu teclado não manda a força da tecla');
    });
  });

  group('pedal', () {
    /// Dois acordes (em 0 e em 1000 ms), tocados e com o pedal que [pedal]
    /// monta.
    _Scene chords(
      void Function(_Scene) pedal, {
      List<double> at = const [0, 1000],
    }) {
      final s = _Scene();
      for (final t in at) {
        s.play(s.note('a$t', 60, t, t + 500, staff: 1));
      }
      pedal(s);
      return s;
    }

    test('a troca 100 ms depois do acorde passa', () {
      final s = chords((s) {
        s.capture.pedal(127, 0);
        s.capture.pedal(0, 1100);
        s.capture.pedal(127, 1120);
      });

      final r = meterPedal(s.input(changes: const [0, 1000]), target: 100);

      expect(r.value, 100);
      expect(r.passed, isTrue);
    });

    test('o pedal preso por dois acordes é borrão', () {
      final s = chords((s) => s.capture.pedal(127, 0), at: const [1000, 2000]);

      final r = meterPedal(s.input(changes: const [1000, 2000]), target: 100);

      expect(r.value, 0);
      expect(r.passed, isFalse);
      expect(
        r.sentence,
        '0 de 2 trocas de pedal limpas; 2 borradas (c. 2, 3).',
      );
    });

    test('o pedal que sobe antes do acorde e desce tarde é buraco', () {
      final s = chords((s) {
        s.capture.pedal(0, 500);
        s.capture.pedal(127, 1600);
      }, at: const [1000]);

      final r = meterPedal(s.input(changes: const [1000]));

      expect(r.value, 0);
      expect(r.sentence, '0 de 1 trocas de pedal limpas; 1 com buraco (c. 2).');
    });

    test('pedal ausente dá o aviso se o pass pede pedal', () {
      final s = chords((_) {});

      final pedido = meterPedal(s.input(changes: const [0], pedal: true));
      final semPedido = meterPedal(s.input(changes: const [0]));

      expect(pedido.value.isNaN, isTrue);
      expect(
        pedido.sentence,
        'nenhum pedal chegou do teclado; ele está ligado?',
      );
      expect(semPedido.sentence, 'nada para medir aqui');
    });
  });

  group('steadiness', () {
    _Scene steady(List<double> offsets) {
      final s = _Scene();
      for (var i = 0; i < offsets.length; i++) {
        final e = s.note('n$i', 60, i * 1000.0, i * 1000.0 + 500);
        s.play(e, on: e.onMs + offsets[i]);
      }
      return s;
    }

    test('atrasos de 0, 10, -10 e 0 ms: desvio de 7 ms passa a meta de 40', () {
      final r = meterSteadiness(steady([0, 10, -10, 0]).input(), target: 40);

      expect(r.value, closeTo(7.07, 0.01));
      expect(r.passed, isTrue);
    });

    test('atrasos de 0, 100, -100 e 0 ms: desvio de 71 ms não passa', () {
      final r = meterSteadiness(steady([0, 100, -100, 0]).input(), target: 40);

      expect(r.value, closeTo(70.71, 0.01));
      expect(r.passed, isFalse);
    });

    test('o desvio sai em ms de parede, dividido pelo andamento', () {
      final r = meterSteadiness(steady([0, 10, -10, 0]).input(speed: 0.5));

      expect(r.value, closeTo(14.14, 0.01));
    });

    test('a frase diz se o aluno corre ou arrasta', () {
      final arrasta = meterSteadiness(steady([50, 50, 50, 50]).input());
      final corre = meterSteadiness(steady([-50, -50, -50, -50]).input());

      expect(arrasta.sentence, 'desvio de 0 ms; arrasta 50 ms em média.');
      expect(corre.sentence, 'desvio de 0 ms; corre 50 ms em média.');
    });
  });

  group('swing', () {
    test('colcheias retas, tocadas a 50% do tempo, dão 50', () {
      final s = _Scene();
      s.play(s.note('e1', 60, 0, 500));
      s.play(s.note('e2', 62, 500, 1000));

      final r = meterSwing(s.input(beats: const [0, 1000]));

      expect(r.value, closeTo(50, 0.01));
      expect(r.sentence, startsWith('a segunda colcheia cai em 50%'));
    });

    test('a segunda colcheia tocada a 67% do tempo, dá 67', () {
      final s = _Scene();
      s.play(s.note('e1', 60, 0, 500));
      s.play(s.note('e2', 62, 500, 1000), on: 667);

      final r = meterSwing(s.input(beats: const [0, 1000]));

      expect(r.value, closeTo(66.7, 0.01));
    });

    test('um tempo sem duas colcheias não entra', () {
      final s = _Scene();
      s.play(s.note('a', 60, 0, 1000));

      final r = meterSwing(s.input(beats: const [0, 1000]));

      expect(r.value.isNaN, isTrue);
      expect(r.passed, isNull);
    });

    test('com a faixa do pass, a mediana tem de cair dentro dela (EX08)', () {
      final s = _Scene();
      s.play(s.note('e1', 60, 0, 500));
      s.play(s.note('e2', 62, 500, 1000), on: 667);

      final dentro = meterSwing(
        s.input(beats: const [0, 1000]),
        range: (60, 70),
      );
      final fora = meterSwing(s.input(beats: const [0, 1000]), range: (45, 55));

      expect(dentro.passed, isTrue);
      expect(fora.passed, isFalse);
      expect(fora.sentence, endsWith('a faixa pedida é 45-55.'));
    });
  });

  group('accents', () {
    _Scene accented(int accent) {
      final s = _Scene();
      s.play(s.note('x', 60, 0, 500), velocity: accent);
      s.play(s.note('y', 62, 500, 1000), velocity: 80);
      s.play(s.note('z', 64, 1000, 1500), velocity: 80);
      s.play(s.note('w', 65, 1500, 2000), velocity: 80);
      return s;
    }

    const marks = ExpressionMarks(accents: {'x'});

    test('o acento 20 mais forte que o resto passa a meta de 12', () {
      final r = meterAccents(accented(100).input(marks: marks), target: 12);

      expect(r.value, 20);
      expect(r.passed, isTrue);
    });

    test('o acento só 5 mais forte não passa', () {
      final r = meterAccents(accented(85).input(marks: marks), target: 12);

      expect(r.value, 5);
      expect(r.passed, isFalse);
      expect(r.measures, [0]);
    });

    test('velocities iguais dão o aviso do teclado', () {
      final r = meterAccents(accented(80).input(marks: marks), target: 12);

      expect(r.sentence, 'seu teclado não manda a força da tecla');
      expect(r.passed, isNull);
    });
  });

  group('choruses', () {
    /// Um compasso de cada ocorrência 0 a 5, sem erro, e o erro que [wrongAt]
    /// põe em um compasso.
    PracticeReport report({int? wrongAt}) => PracticeReport([
      for (var m = 0; m < 6; m++)
        ReportEntry(
          const NoteVerdict(
            eventId: 'x',
            pitch: 60,
            kind: PracticeVerdictKind.correct,
            deltaMs: 0,
          ),
          m,
        ),
      if (wrongAt != null)
        ReportEntry(
          const NoteVerdict(
            pitch: 61,
            kind: PracticeVerdictKind.wrong,
            deltaMs: 0,
          ),
          wrongAt,
        ),
    ]);

    test('três voltas, sem nenhum erro, dão 3', () {
      final s = _Scene();
      final r = meterChoruses(
        s.input(
          report: report(),
          chorusStarts: const [0, 2, 4],
          roundDone: true,
        ),
      );

      expect(r.value, 3);
      expect(r.sentence, '3 voltas seguidas sem erro, de 3 completas.');
    });

    test('um erro na segunda volta quebra a sequência', () {
      final s = _Scene();
      final r = meterChoruses(
        s.input(
          report: report(wrongAt: 2),
          chorusStarts: const [0, 2, 4],
          roundDone: true,
        ),
      );

      expect(r.value, 1);
      expect(r.measures, [2]);
    });

    test('a última volta só conta quando a rodada acabou', () {
      final s = _Scene();
      final r = meterChoruses(
        s.input(report: report(), chorusStarts: const [0, 2, 4]),
      );

      expect(r.value, 2);
      expect(r.sentence, '2 voltas seguidas sem erro, de 2 completas.');
    });

    test('com `choruses` do pass, chega ao alvo ou reprova (EX08)', () {
      final s = _Scene();
      final dois = meterChoruses(
        s.input(
          report: report(),
          chorusStarts: const [0, 2, 4],
          roundDone: true,
        ),
        target: 2,
      );
      final tres = meterChoruses(
        s.input(
          report: report(wrongAt: 2),
          chorusStarts: const [0, 2, 4],
          roundDone: true,
        ),
        target: 2,
      );

      expect(dois.passed, isTrue);
      expect(tres.passed, isFalse);
    });
  });

  test('allMeters devolve os nove, na ordem da tabela', () {
    final s = _Scene();
    s.play(s.note('a', 60, 0, 500));

    final ids = allMeters(s.input()).map((r) => r.id);

    expect(ids, [
      'legato',
      'staccato',
      'dynamics',
      'balance',
      'pedal',
      'steadiness',
      'swing',
      'accents',
      'choruses',
    ]);
  });
}

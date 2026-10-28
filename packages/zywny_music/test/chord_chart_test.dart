// EX09 — `chord_chart.dart`: a grade lida, expandida e posta no tempo.

import 'package:test/test.dart';

import 'package:zywny_music/chord.dart';
import 'package:zywny_music/chord_chart.dart';
import 'package:zywny_music/chord_degree.dart';

ChordChart _grade(String text, {String key = 'C', String time = '4/4'}) {
  final errors = <String>[];
  final chart = ChordChart.parse(
    text,
    key: KeySpec.parse(key)!,
    time: time,
    error: (message, col) => errors.add('$col: $message'),
  );
  expect(errors, isEmpty, reason: 'a grade `$text` não devia ter erro');
  return chart!;
}

String _name(ChartSlot slot) =>
    slot.chord?.label(ChordNotation.american) ?? '-';

void main() {
  group('repetições', () {
    test('|: C | Am | F G | C :| expande em 8 compassos', () {
      final chart = _grade('|: C | Am | F G | C :|');
      final played = chart.expand();
      expect(played, hasLength(8));
      expect(played.map((p) => p.writtenBar), [0, 1, 2, 3, 0, 1, 2, 3]);
      expect(played.map((p) => p.chorus), [1, 1, 1, 1, 2, 2, 2, 2]);
    });

    test('F e G de 2 tempos cada, nas duas voltas', () {
      final slots = _grade('|: C | Am | F G | C :|').slots();
      expect(slots, hasLength(10));
      final fg = slots.where((s) => _name(s) == 'F' || _name(s) == 'G');
      expect(fg, hasLength(4));
      for (final slot in fg) {
        expect(slot.beats, 2);
      }
      // Cada compasso de 4/4 tem 4 tempos: a 8ª ocorrência começa no 28.
      expect(slots.last.startBeat, 28);
      expect(slots.last.barOccurrence, 7);
    });

    test(':| x3 toca a repetição três vezes', () {
      final played = _grade('|: C | G :| x3').expand();
      expect(played.map((p) => p.writtenBar), [0, 1, 0, 1, 0, 1]);
      expect(played.map((p) => p.chorus), [1, 1, 2, 2, 3, 3]);
    });

    test('sem |:, a repetição começa no primeiro compasso', () {
      final played = _grade('C | Am :|').expand();
      expect(played.map((p) => p.writtenBar), [0, 1, 0, 1]);
    });

    test('a 1ª e a 2ª casa: a 1ª na primeira volta, a 2ª na última', () {
      // A casa vai até o `]`; sem ele, a 2ª casa engole o compasso seguinte.
      final chart = _grade('|: C | Am [1 F :| [2 G ] | C |');
      final played = chart.expand();
      expect(played, [
        const PlayedBar(writtenBar: 0, chorus: 1),
        const PlayedBar(writtenBar: 1, chorus: 1),
        const PlayedBar(writtenBar: 2, chorus: 1),
        const PlayedBar(writtenBar: 0, chorus: 2),
        const PlayedBar(writtenBar: 1, chorus: 2),
        const PlayedBar(writtenBar: 3, chorus: 2),
        const PlayedBar(writtenBar: 4, chorus: 1),
      ]);
    });
  });

  group('tempo e acordes', () {
    test('| F . G . | dá F F G G, um tempo cada', () {
      final slots = _grade('| F . G . |').slots();
      expect(slots.map(_name), ['F', 'F', 'G', 'G']);
      expect(slots.map((s) => s.beats), [1, 1, 1, 1]);
      expect(slots.map((s) => s.startBeat), [0, 1, 2, 3]);
    });

    test('em 3/4, dois acordes dão 2 + 1 tempos', () {
      final slots = _grade('| F G |', time: '3/4').slots();
      expect(slots.map((s) => s.beats), [2, 1]);
    });

    test('em 6/8 o compasso tem dois tempos (pontuados)', () {
      final chart = _grade('| C |', time: '6/8');
      expect(chart.beatsPerBar, 2);
      expect(chart.slots().single.beats, 2);
    });

    test('% repete o compasso anterior', () {
      final chart = _grade('| C | % | G |');
      expect(chart.bars[1].chords.map((c) => c.degree), ['I']);
      expect(chart.expand(), hasLength(3));
    });

    test('N.C. é um acorde sem cifra', () {
      final slot = _grade('| N.C. |').slots().single;
      expect(slot.chord, isNull);
      expect(slot.degree, 'N.C.');
    });
  });

  group('graus', () {
    test('em F, ii7 V7 I resolve em Gm7 C7 F', () {
      final chart = _grade('| ii7 V7 | I |', key: 'F');
      final slots = chart.slots();
      expect(slots[0].chord!.rootSpelling, 'G');
      expect(slots[0].chord!.quality, ChordQuality.minor7);
      expect(slots[1].chord!.rootSpelling, 'C');
      expect(slots[1].chord!.quality, ChordQuality.dominant7);
      expect(slots[2].chord!.rootSpelling, 'F');
      expect(slots.map((s) => s.degree), ['ii7', 'V7', 'I']);
    });

    test('uma cifra escrita ganha o grau no tom', () {
      final slots = _grade('| G7 | Am | F |', key: 'C').slots();
      expect(slots.map((s) => s.degree), ['V7', 'vi', 'IV']);
    });
  });

  group('biblioteca (fromProgression)', () {
    test('blues-12 em G, com bars: 24, repete a progressão duas vezes', () {
      final chart = ChordChart.fromProgression(
        'blues-12',
        key: KeySpec.parse('G')!,
        bars: 24,
      );
      expect(chart.bars, hasLength(24));
      expect(chart.expand(), hasLength(24));
      final first = chart.slots().first;
      expect(first.chord!.root, 7);
      expect(first.degree, 'I7');
      // Os compassos 13 a 24 repetem o blues: o 13º é o I7 de novo.
      expect(chart.slots()[12].degree, 'I7');
    });

    test('uma progressão sem bars toca só o que ela tem', () {
      final chart = ChordChart.fromProgression(
        'ii-V-I',
        key: KeySpec.parse('C')!,
      );
      expect(chart.bars, hasLength(4));
    });

    test('uma progressão que não existe lança ArgumentError', () {
      expect(
        () =>
            ChordChart.fromProgression('nao-existe', key: KeySpec.parse('C')!),
        throwsArgumentError,
      );
    });
  });

  group('seções', () {
    test('A: e B: começam seções nos compassos certos', () {
      final chart = _grade('A: | C | Am |\nB: | F | G |');
      expect(chart.sections, [
        const ChartSection(label: 'A', firstBar: 0),
        const ChartSection(label: 'B', firstBar: 2),
      ]);
    });
  });

  group('transposição', () {
    test('C para E♭ escreve A♭ (e não G♯), e G♯ vira B', () {
      final chart = _grade('| F | G# |').transposedTo(KeySpec.parse('Eb')!);
      final slots = chart.slots();
      expect(slots[0].chord!.root, 8);
      expect(slots[0].chord!.rootSpelling, 'Ab');
      expect(slots[1].chord!.root, 11);
      expect(slots[1].chord!.rootSpelling, 'B');
      expect(chart.key, KeySpec.parse('Eb'));
    });

    test('o grau não muda ao transpor', () {
      final chart = _grade('| ii7 V7 |', key: 'C');
      final moved = chart.transposedTo(KeySpec.parse('Bb')!);
      expect(moved.slots().map((s) => s.degree), ['ii7', 'V7']);
      expect(moved.slots().first.chord!.rootSpelling, 'C');
    });

    test('a fundamental do baixo anda junto', () {
      final chart = _grade('| F/A |').transposedTo(KeySpec.parse('Eb')!);
      final chord = chart.slots().single.chord!;
      expect(chord.rootSpelling, 'Ab');
      expect(chord.bassSpelling, 'C');
    });
  });

  group('erros', () {
    test('uma cifra inválida dá a coluna e não devolve a grade', () {
      final errors = <(String, int)>[];
      final chart = ChordChart.parse(
        '| C | Hm |',
        key: KeySpec.parse('C')!,
        error: (message, col) => errors.add((message, col)),
      );
      expect(chart, isNull);
      expect(errors, hasLength(1));
      expect(errors.single.$1, contains('`Hm` não é uma cifra'));
      expect(errors.single.$2, 7);
    });

    test('|: sem :| que a feche é erro', () {
      final errors = <(String, int)>[];
      final chart = ChordChart.parse(
        '|: C | G',
        key: KeySpec.parse('C')!,
        error: (message, col) => errors.add((message, col)),
      );
      expect(chart, isNull);
      expect(errors.single.$1, contains('sem um `:|`'));
      expect(errors.single.$2, 1);
    });

    test('um compasso de tempo desconhecido é recusado', () {
      final errors = <String>[];
      final chart = ChordChart.parse(
        '| C |',
        key: KeySpec.parse('C')!,
        time: '5/16',
        error: (message, col) => errors.add(message),
      );
      expect(chart, isNull);
      expect(errors.single, contains('5/16'));
    });

    test('uma grade sem compassos é recusada', () {
      final errors = <String>[];
      final chart = ChordChart.parse(
        '   \n',
        key: KeySpec.parse('C')!,
        error: (message, col) => errors.add(message),
      );
      expect(chart, isNull);
      expect(errors, ['a grade não tem compassos']);
    });
  });
}

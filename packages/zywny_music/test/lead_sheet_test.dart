// EX17 — a grade da lead sheet (`leadSheetChords`): as cifras do `<harmony>` do
// MusicXML com a hora e a duração exatas, a grafia `text` (`7M`), o acorde
// sobre uma pausa, o baixo, e os erros com o compasso.

import 'package:test/test.dart';
import 'package:zywny_music/lead_sheet.dart';
import 'package:zywny_music/melody_xml.dart';

/// Um MusicXML de uma parte em 4/4 com os compassos [bars] (o conteúdo de cada
/// `<measure>`, sem os atributos, que vão no primeiro).
String _xml(List<String> bars) {
  final measures = [
    for (var m = 0; m < bars.length; m++)
      '<measure number="${m + 1}">'
          '${m == 0 ? '<attributes><divisions>1</divisions><key><fifths>0</fifths>'
                    '</key><time><beats>4</beats><beat-type>4</beat-type></time>'
                    '</attributes>' : ''}'
          '${bars[m]}</measure>',
  ].join('\n');
  return '<?xml version="1.0"?>\n<score-partwise version="3.1"><part-list>'
      '<score-part id="P1"><part-name>M</part-name></score-part></part-list>'
      '<part id="P1">\n$measures\n</part></score-partwise>';
}

String _harm(String root, String kind, {String? text, String? bass}) {
  final k = text == null
      ? '<kind>$kind</kind>'
      : '<kind text="$text">$kind</kind>';
  final b = bass == null ? '' : '<bass><bass-step>$bass</bass-step></bass>';
  return '<harmony><root><root-step>$root</root-step></root>$k$b</harmony>';
}

const _q =
    '<note><pitch><step>C</step><octave>5</octave></pitch>'
    '<duration>1</duration><voice>1</voice><type>quarter</type></note>';

MelodyScore _score(String xml) {
  final score = readMelodyXml(xml);
  expect(score, isNotNull);
  return score!;
}

void main() {
  test('as cifras dão a hora, a duração e o compasso de cada uma', () {
    final score = _score(
      _xml([
        '${_harm('C', 'major-seventh')}$_q$_q$_q$_q',
        '${_harm('G', 'dominant')}$_q$_q'
            '${_harm('A', 'minor-seventh')}$_q$_q',
      ]),
    );
    final chords = leadSheetChords(score);
    expect(chords, isNotNull);
    expect([for (final c in chords!) c.label], ['Cmaj7', 'G7', 'Am7']);
    expect([for (final c in chords) c.start], [0, 4, 6]);
    expect([for (final c in chords) c.beats], [4, 2, 2]);
    expect([for (final c in chords) c.bar], [0, 1, 1]);
    expect(chords.first.chord.root, 0);
    expect(chords[1].chord.pitchClasses, contains(11), reason: 'G7 tem o Fá');
  });

  test('a grafia `text` do arquivo vale: `7M` sai como `C7M` e lê o maj7', () {
    final score = _score(
      _xml(['${_harm('C', 'major-seventh', text: '7M')}$_q$_q$_q$_q']),
    );
    final chords = leadSheetChords(score)!;
    expect(chords.single.label, 'C7M');
    expect(chords.single.chord.pitchClasses, {0, 4, 7, 11});
  });

  test('o `text` com `(b5)` e o baixo (`C/E`) saem na grafia da EX01', () {
    final score = _score(
      _xml([
        '${_harm('B', 'half-diminished', text: 'm7(b5)')}$_q$_q$_q$_q',
        '${_harm('C', 'major', bass: 'E')}$_q$_q$_q$_q',
      ]),
    );
    final chords = leadSheetChords(score)!;
    expect(chords[0].label, 'Bm7(b5)');
    expect(chords[0].chord.pitchClasses, {11, 2, 5, 9});
    expect(chords[1].label, 'C/E');
    expect(chords[1].chord.bass, 4);
  });

  test('um acorde sobre uma pausa começa na pausa', () {
    final score = _score(
      _xml([
        '${_harm('D', 'minor')}<note><rest/><duration>2</duration>'
            '<voice>1</voice><type>half</type></note>'
            '${_harm('A', 'minor')}$_q$_q',
        '${_harm('G', 'dominant')}$_q$_q$_q$_q',
      ]),
    );
    final chords = leadSheetChords(score)!;
    expect([for (final c in chords) c.start], [0, 2, 4]);
    expect([for (final c in chords) c.label], ['Dm', 'Am', 'G7']);
    expect([for (final c in chords) c.beats], [2, 2, 4]);
  });

  test('a troca no meio do compasso sai com o tempo que tem', () {
    final score = _score(
      _xml([
        '${_harm('F', 'major')}$_q${_harm('C', 'major')}$_q$_q$_q',
        '${_harm('G', 'dominant')}$_q$_q$_q$_q',
      ]),
    );
    final chords = leadSheetChords(score)!;
    expect([for (final c in chords) c.start], [0, 1, 4]);
    expect([for (final c in chords) c.beats], [1, 3, 4]);
    expect([for (final c in chords) c.bar], [0, 0, 1]);
  });

  group('erros, com o compasso', () {
    test('uma partitura sem cifra', () {
      final messages = <String>[];
      final chords = leadSheetChords(
        _score(_xml(['$_q$_q$_q$_q'])),
        error: messages.add,
      );
      expect(chords, isNull);
      expect(messages.single, 'a partitura não tem cifras (`<harmony>`)');
    });

    test('a primeira cifra depois do começo', () {
      final messages = <String>[];
      final chords = leadSheetChords(
        _score(_xml(['$_q$_q${_harm('C', 'major')}$_q$_q'])),
        error: messages.add,
      );
      expect(chords, isNull);
      expect(messages.single, contains('o compasso 1 não tem cifra'));
    });

    test('um tipo de acorde sem nome na grafia da EX01', () {
      final messages = <String>[];
      final chords = leadSheetChords(
        _score(
          _xml([
            '${_harm('C', 'major')}$_q$_q$_q$_q',
            '${_harm('D', 'pedal')}$_q$_q$_q$_q',
          ]),
        ),
        error: messages.add,
      );
      expect(chords, isNull);
      expect(messages.single, contains('o compasso 2'));
      expect(messages.single, contains('pedal'));
    });

    test('uma cifra que a EX01 não lê, com o compasso', () {
      final messages = <String>[];
      final chords = leadSheetChords(
        _score(
          _xml([
            '${_harm('C', 'major')}$_q$_q$_q$_q',
            '${_harm('D', 'major', text: 'zz9')}$_q$_q$_q$_q',
          ]),
        ),
        error: messages.add,
      );
      expect(chords, isNull);
      expect(messages.single, startsWith('o compasso 2: a cifra `Dzz9`'));
    });
  });
}

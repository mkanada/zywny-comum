import 'package:test/test.dart';
import 'package:zywny_music/melody_xml.dart';

/// Um MusicXML mínimo: uma parte, armadura de um sustenido (Sol maior), 4/4.
/// O compasso 1 tem uma ligadura (dó que dura 2 semínimas), o 2 tem um acorde
/// na melodia, uma apojatura, um `backup` com outra voz e a marca `chg`.
const _xml = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "">
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>M</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>1</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><direction-type><words>chg</words></direction-type></direction>
      <note xml:id="n1"><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><tie type="start"/></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><tie type="stop"/></note>
    </measure>
    <measure number="2">
      <note><grace/><pitch><step>B</step><octave>4</octave></pitch><duration>0</duration></note>
      <note xml:id="n2"><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration></note>
      <note><chord/><pitch><step>F</step><alter>1</alter><octave>5</octave></pitch><duration>1</duration></note>
      <backup><duration>4</duration></backup>
      <note><voice>2</voice><pitch><step>C</step><octave>3</octave></pitch><duration>4</duration></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration></note>
      <direction><direction-type><words>chg</words></direction-type></direction>
      <note><rest/><duration>2</duration></note>
    </measure>
  </part>
</score-partwise>
''';

void main() {
  group('readMelodyXml', () {
    test('lê as notas, a ligadura e o acorde na melodia', () {
      final score = readMelodyXml(_xml)!;
      final notes = score.notes;
      // C5 ligado (2 + 2 semínimas num só); no tempo 4, o F#5 do acorde troca
      // o D5, por ser o mais agudo, e fica com o id do D5 (que o acorde não tem).
      expect([for (final n in notes) n.pitch], [72, 78, 76]);
      expect(notes[0].start, 0);
      expect(notes[0].beats, 4);
      expect(notes[0].id, 'n1');
      expect(notes[1].start, 4);
      expect(notes[1].beats, 1);
      expect(notes[1].id, 'n2');
    });

    test('a voz 2 não entra, mas o tempo do backup volta', () {
      final score = readMelodyXml(_xml)!;
      // O backup volta o tempo ao do D5: o E5 sai no tempo 5, e não depois do
      // C3 da voz 2 (que dura 4 e não entra).
      final e5 = score.notes.last;
      expect(e5.pitch, 76);
      expect(e5.start, 5);
    });

    test('a armadura dá a tônica (Sol maior = 7; Mi menor = 4)', () {
      final score = readMelodyXml(_xml)!;
      expect(score.fifths, 1);
      expect(score.minor, isFalse);
      expect(score.tonicPc, 7);
      expect(score.time, '4/4');
    });

    test('as marcas chg dão a hora delas em semínimas', () {
      final score = readMelodyXml(_xml)!;
      // Uma no começo (0) e a do compasso 2, depois do E5 (que vai de 5 a 7):
      // a marca está em 7.
      expect(score.changes, [0, 7]);
    });

    test('compassos: começo e tamanho', () {
      final score = readMelodyXml(_xml)!;
      expect(score.measures, hasLength(2));
      expect(score.measures[1].start, 4);
      expect(score.measures[1].beats, 4);
    });

    test('arquivo que não é partitura dá erro, não exceção', () {
      final messages = <String>[];
      expect(readMelodyXml('<foo/>', error: messages.add), isNull);
      expect(messages, hasLength(1));
    });

    test('parte sem nota dá erro', () {
      const empty = '''
<score-partwise><part id="P1">
  <measure number="1"><attributes><divisions>1</divisions></attributes>
  <note><rest/><duration>4</duration></note></measure>
</part></score-partwise>''';
      final messages = <String>[];
      expect(readMelodyXml(empty, error: messages.add), isNull);
      expect(messages.single, contains('nenhuma nota'));
    });

    test('sem armadura, o tom é desconhecido', () {
      const plain = '''
<score-partwise><part id="P1">
  <measure number="1"><attributes><divisions>1</divisions>
  <time><beats>3</beats><beat-type>4</beat-type></time></attributes>
  <note><pitch><step>A</step><octave>4</octave></pitch><duration>3</duration></note>
  </measure>
</part></score-partwise>''';
      final score = readMelodyXml(plain)!;
      expect(score.fifths, isNull);
      expect(score.tonicPc, isNull);
      expect(score.time, '3/4');
      expect(score.notes.single.pitch, 69);
    });
  });
}

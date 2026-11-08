// LP01: o retrato do Verovio para o medidor (`readScoreMusic`) traz os mesmos
// ids de nota que o desenho da partitura (`renderBytes`), com as mesmas opções.
// Sem a `libverovio.so` o teste é pulado. A cena e o pitchpos são lidos do JSON
// que o próprio Verovio devolve; nada aqui lê o MusicXML.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/render_helper.dart';

/// Quatro semínimas por compasso em Mi♭ maior (3♭), com uma barra de
/// repetição no fim (a mesma partitura do `vsb_render_test.dart`).
final Uint8List _eflatMajorXml = () {
  String note(String step, int alter, int octave) =>
      '<note><pitch><step>$step</step>'
      '${alter == 0 ? '' : '<alter>$alter</alter>'}'
      '<octave>$octave</octave></pitch>'
      '<duration>1</duration><type>quarter</type></note>';
  return Uint8List.fromList(
    utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>-3</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      ${note('E', -1, 4)}${note('F', 0, 4)}${note('G', 0, 4)}${note('A', -1, 4)}
    </measure>
    <measure number="2">
      ${note('B', -1, 4)}${note('C', 0, 5)}${note('D', 0, 5)}${note('E', -1, 5)}
      <barline location="right">
        <bar-style>light-heavy</bar-style>
        <repeat direction="backward"/>
      </barline>
    </measure>
  </part>
</score-partwise>
'''),
  );
}();

/// O retrato lido: o bridge já decodificado e os atributos por id.
typedef _Snapshot = ({
  Map<String, dynamic> bridge,
  Map<String, dynamic> attributes,
});

Future<_Snapshot> _read({Map<String, Object> options = const {}}) async {
  final snapshot = await readMusicBytes(
    _eflatMajorXml,
    'hino.musicxml',
    options: options,
  );
  final decoded = jsonDecode(snapshot.json) as Map<String, dynamic>;
  return (
    bridge: jsonDecode(decoded['bridge'] as String) as Map<String, dynamic>,
    attributes: decoded['attributes'] as Map<String, dynamic>,
  );
}

/// Visita cada nó da cena (compasso, pauta, voz, nota, pausa…) com id e classe.
void _walkScene(Object? node, void Function(Map node) visit) {
  if (node is Map) {
    if (node['id'] is String && node['class'] is String) visit(node);
    _walkScene(node['children'], visit);
    _walkScene(node['pages'], visit);
    _walkScene(node['root'], visit);
  } else if (node is List) {
    for (final child in node) {
      _walkScene(child, visit);
    }
  }
}

/// Os ids dos nós de classe [cls] da cena, na ordem em que aparecem.
List<String> _idsOf(Map<String, dynamic> bridge, String cls) {
  final ids = <String>[];
  _walkScene(bridge['scene'], (node) {
    if (node['class'] == cls) ids.add(node['id'] as String);
  });
  return ids;
}

void main() {
  final skip = verovioAvailable ? null : 'libverovio.so do bridge ausente';

  test(
    'o retrato traz timemap e o n de todo compasso, pauta e voz da cena',
    () async {
      final snapshot = await _read(options: {'xmlIdSeed': 1});

      final timemap = snapshot.bridge['timemap'];
      expect(timemap, isA<List>());
      expect(timemap as List, isNotEmpty);

      final measures = _idsOf(snapshot.bridge, 'measure');
      final staves = _idsOf(snapshot.bridge, 'staff');
      final layers = _idsOf(snapshot.bridge, 'layer');
      expect(measures, isNotEmpty);
      expect(staves, isNotEmpty);
      expect(layers, isNotEmpty);
      for (final id in [...measures, ...staves, ...layers]) {
        expect(
          snapshot.attributes[id]?['n'],
          isNotNull,
          reason: 'o n do elemento $id',
        );
      }
    },
    skip: skip,
  );

  test(
    'os ids das notas do retrato são os do desenho (os da midi.json)',
    () async {
      final snapshot = await _read(options: {'xmlIdSeed': 1});
      final sceneNotes = _idsOf(snapshot.bridge, 'note');

      final drawn = await renderBytes(
        _eflatMajorXml,
        'hino.musicxml',
        options: {'xmlIdSeed': 1},
      );
      // Os ids com `-rend` (ex.: `-rend2`) são a segunda passada da repetição:
      // a cena é a escrita, uma vez, e não os tem (o timemap os cobre).
      final writtenIds = drawn.midi!.notes
          .map((n) => n.id)
          .where((id) => !id.contains('-rend'))
          .toList();

      expect(writtenIds.length, greaterThanOrEqualTo(4));
      expect(sceneNotes, containsAll(writtenIds));
    },
    skip: skip,
  );

  test('com transpose "-m3" os ids continuam batendo e a primeira nota cai 3 '
      'semitons (mi♭4 vira dó4) no retrato e no desenho', () async {
    const options = {'xmlIdSeed': 1, 'transpose': '-m3'};
    final snapshot = await _read(options: options);
    final sceneNotes = _idsOf(snapshot.bridge, 'note');

    final drawn = await renderBytes(
      _eflatMajorXml,
      'hino.musicxml',
      options: options,
    );
    // Sem os `-rend` (ver o teste acima): esses são da repetição, fora da cena.
    final writtenIds = drawn.midi!.notes
        .map((n) => n.id)
        .where((id) => !id.contains('-rend'))
        .toList();
    expect(sceneNotes, containsAll(writtenIds));

    // A primeira nota do retrato (a primeira da cena) no contexto de notação:
    // o `pitchpos` traz o passo (`pn`) e a oitava (`o`) já transpostos.
    final firstId = sceneNotes.first;
    final pitch =
        (snapshot.bridge['pitchpos'] as Map)['events'][firstId] as Map;
    expect(pitch['pn'], 'c');
    expect(pitch['o'], 4);

    // E o desenho diz o mesmo em semitons: 63 (mi♭4) menos 3.
    expect(drawn.midi!.notes.first.pitch, 60);
  }, skip: skip);

  test('sem a transposição a primeira nota continua mi♭4 no retrato', () async {
    final snapshot = await _read(options: {'xmlIdSeed': 1});
    final firstId = _idsOf(snapshot.bridge, 'note').first;
    final pitch =
        (snapshot.bridge['pitchpos'] as Map)['events'][firstId] as Map;
    expect(pitch['pn'], 'e');
    expect(pitch['o'], 4);
  }, skip: skip);
}

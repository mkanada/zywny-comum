// Integração ponta a ponta do caminho novo: MEI -> libverovio (FFI, isolate)
// -> `.vsb` -> parser do score_bridge -> ScenePainter.
//
// Depende de dois artefatos não versionados; sem eles o teste é pulado em vez
// de falhar (ver README.md, seção Build):
//   tool/build_verovio_linux.sh  -> libverovio.so no verovio_flutter_bridge
//
// `verovioResourcePath()` não serve aqui: depende de path_provider, que não
// tem implementação em `flutter test`. O resourcePath aponta direto para o
// `verovio/data` do verovio_flutter_bridge, que é a mesma árvore que o zip empacota.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/verovio_render.dart';

import 'support/render_helper.dart';

final _scorePath = '$kVerovioBridge/corpus/mei/Grieg_Little_bird_Op43_No4.mei';

/// Quatro semínimas por compasso em Mi♭ maior (3♭), com uma barra de
/// repetição no fim: o documento expandido (`-rend`) também sai transposto.
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

/// A mesma semente nos dois renders: os ids de nota saem iguais (Q01).
Future<VsbDocument> _renderEflat({String? transpose}) => renderBytes(
  _eflatMajorXml,
  'hino.musicxml',
  options: {'xmlIdSeed': 1, 'transpose': ?transpose},
);

/// Quantos acidentes tem a armadura vigente na primeira nota.
int _keyAccidentals(VsbDocument doc) =>
    doc.pitchPos!.events[doc.midi!.notes.first.id]!.key.length;

void main() {
  // `loadScoreFonts` passa pelo `rootBundle`, que exige o binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final missing = [
    kLibverovioPath,
    kVerovioDataPath,
    _scorePath,
  ].where((p) => !File(p).existsSync() && !Directory(p).existsSync()).toList();

  test(
    'gera e desenha um .vsb a partir de um MEI do corpus',
    () async {
      final tmp = await Directory.systemTemp.createTemp('zywny_test');
      addTearDown(() => tmp.delete(recursive: true));

      final document = await renderScoreToVsb(
        VsbRenderRequest(
          inputPath: _scorePath,
          outputPath: '${tmp.path}/score.vsb',
          libraryPath: File(kLibverovioPath).absolute.path,
          resourcePath: Directory(kVerovioDataPath).absolute.path,
          pageWidth: kFallbackPageWidth,
          pageHeight: kFallbackPageHeight,
        ),
      );

      expect(document.pages, isNotEmpty);
      expect(document.manifest.pageCount, document.pages.length);
      expect(document.glyphs, isNotEmpty);

      // N02 (zywny): document.midi chega populado depois de G01/G02 no bridge
      // (libverovio.so refeita por `just native`).
      expect(document.midi, isNotNull);
      expect(document.midi!.notes, isNotEmpty);

      // G05: pitchpos.json e a geometria de pauta chegam pelo mesmo caminho,
      // e uma tecla qualquer vira fantasma na coluna de uma nota real.
      expect(document.pitchPos, isNotNull);
      final firstNote = document.midi!.notes.first;
      final ghosts = document.ghostsFor(
        expectedIds: [firstNote.id],
        wrongKeys: [firstNote.pitch + 1],
      );
      expect(ghosts, hasLength(1));
      expect(ghosts.single.head.glyphId, endsWith(':E0A4'));

      // O pintor só quebra na página real: glifos ausentes do dicionário e
      // runs de texto sem fonte carregada falham aqui, não no parse.
      await loadScoreFonts();
      final recorder = ui.PictureRecorder();
      ScenePainter(
        document.pages.first,
        document.glyphs,
        glyphCache: document.glyphCache,
      ).paint(ui.Canvas(recorder));
      recorder.endRecording().dispose();
    },
    skip: missing.isEmpty ? null : 'artefatos ausentes: ${missing.join(', ')}',
  );

  // Q03: a opção `transpose` chega ao Verovio pelo caminho do app. A medição
  // em hinos de todas as armaduras é do Q01 (transposicao_render_manual_test).
  test(
    'transpose "-m3" num hino em 3♭: notas 3 semitons abaixo, mesmos tempos, '
    'armadura vazia',
    () async {
      final original = await _renderEflat();
      final transposed = await _renderEflat(transpose: '-m3');

      // Sem a opção a partitura é a que está escrita: Mi♭ maior, 3♭.
      expect(_keyAccidentals(original), 3);
      expect(original.midi!.notes.first.pitch, 63); // Mi♭4

      final a = original.midi!.notes, b = transposed.midi!.notes;
      // 8 notas e as 8 da repetição, todas deslocadas uma vez só.
      expect(a, hasLength(16));
      expect(a.where((n) => n.id.contains('-rend')), hasLength(8));
      expect(b, hasLength(a.length));
      for (var i = 0; i < a.length; i++) {
        expect(b[i].id, a[i].id, reason: 'mesma semente, mesmo id ($i)');
        expect(b[i].pitch, a[i].pitch - 3, reason: 'nota $i');
        expect(b[i].onMs, a[i].onMs, reason: 'início da nota $i');
        expect(b[i].offMs, a[i].offMs, reason: 'fim da nota $i');
        expect(
          [b[i].staff, b[i].layer, b[i].tied],
          [a[i].staff, a[i].layer, a[i].tied],
          reason: 'pauta, camada e ligadura da nota $i',
        );
      }
      // Dó maior: sem acidentes na armadura.
      expect(_keyAccidentals(transposed), 0);
      expect(transposed.midi!.notes.first.pitch, 60); // Dó4

      // O timemap (o que o player e o treino leem) e o layout não mudam.
      final tmA = original.timemap!, tmB = transposed.timemap!;
      expect(tmB, hasLength(tmA.length));
      for (var i = 0; i < tmA.length; i++) {
        expect(tmB[i].tstamp, tmA[i].tstamp);
        expect(tmB[i].on, tmA[i].on);
        expect(tmB[i].off, tmA[i].off);
      }
      expect(transposed.pages, hasLength(original.pages.length));
    },
    skip: verovioAvailable ? false : 'libverovio.so do bridge ausente',
  );
}

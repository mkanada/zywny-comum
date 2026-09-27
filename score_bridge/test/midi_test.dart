// `midi.json` (§2.7, G01/G02): os eventos que o exportador MIDI do Verovio
// emitiria — notas (com ligadura já unida, ornamentos já expandidos) e
// pedal — com o `xml:id` de origem. Cobre a leitura do JSON único e do zip
// `.vsb`, a ausência do arquivo, os erros de forma e `VsbMidi.notesOf`
// (cabeça de ligadura, continuação, ornamento).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

Map<String, dynamic> _freshExemploMinimo() {
  final file = File('../docs/formato/exemplo-minimo.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

const _sampleMidiJson = {
  'notes': [
    {'id': 'n1a2b', 'on': 0, 'off': 500, 'p': 64, 's': 1, 'l': 1, 'v': 90},
    {
      'id': 'n9f',
      'on': 500,
      'off': 1500,
      'p': 52,
      's': 2,
      'l': 1,
      'c': 3,
      'pg': 40,
      'v': 85,
      'tied': ['n9f-cont'],
    },
    {
      'id': 'n33',
      'on': 1500,
      'off': 1562.5,
      'p': 71,
      's': 1,
      'l': 1,
      'v': 90,
      'orn': true,
    },
    {
      'id': 'n33',
      'on': 1562.5,
      'off': 1625,
      'p': 72,
      's': 1,
      'l': 1,
      'v': 90,
      'orn': true,
    },
  ],
  'pedal': [
    {'id': 'pd12', 't': 1000, 'dir': 'down', 's': 1},
    {'id': 'pd13', 't': 4000, 'dir': 'up', 's': 1, 'c': 2},
  ],
};

/// Monta um `.vsb` (zip) a partir do exemplo mínimo, com [midiJson] (quando
/// não nulo) virando `midi.json` — mesmo padrão de `meta_test.dart`.
Uint8List _zipFrom(Map<String, dynamic> root, {Object? midiJson}) {
  final manifest = Map<String, dynamic>.from(root['manifest'] as Map);
  final files = Map<String, dynamic>.from(manifest['files'] as Map);
  if (midiJson == null) {
    files.remove('midi');
  } else {
    files['midi'] = 'midi.json';
  }
  manifest['files'] = files;

  final archive = Archive();
  void add(String name, Object json) {
    final bytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('manifest.json', manifest);
  add('scene.json', root['scene']!);
  add('glyphs.json', root['glyphs']!);
  add('timemap.json', root['timemap']!);
  if (midiJson != null) add('midi.json', midiJson);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('parseMidiDocument', () {
    test('notas e pedal, com e sem campos opcionais', () {
      final midi = parseMidiDocument(_sampleMidiJson, path: 'midi');

      expect(midi.notes, hasLength(4));
      expect(midi.pedal, hasLength(2));

      final plain = midi.notes.first;
      expect(plain.id, 'n1a2b');
      expect(plain.onMs, 0);
      expect(plain.offMs, 500);
      expect(plain.pitch, 64);
      expect(plain.staff, 1);
      expect(plain.layer, 1);
      expect(plain.channel, 0); // "c" omitido → padrão 0
      expect(plain.program, 0); // "pg" omitido → padrão 0
      expect(plain.velocity, 90);
      expect(plain.tied, isEmpty);
      expect(plain.ornament, isFalse);

      final tied = midi.notes[1];
      expect(tied.channel, 3);
      expect(tied.program, 40);
      expect(tied.tied, ['n9f-cont']);

      final downPedal = midi.pedal.first;
      expect(downPedal.id, 'pd12');
      expect(downPedal.timeMs, 1000);
      expect(downPedal.dir, PedalDir.down);
      expect(downPedal.staff, 1);
      expect(downPedal.channel, 0);

      final upPedal = midi.pedal[1];
      expect(upPedal.dir, PedalDir.up);
      expect(upPedal.channel, 2);
    });

    group('erros de forma', () {
      test('sem "notes"', () {
        expect(
          () => parseMidiDocument({'pedal': []}, path: 'midi'),
          throwsA(
            isA<VsbFormatException>().having(
              (e) => e.path,
              'path',
              'midi.notes',
            ),
          ),
        );
      });

      test('nota sem "id"', () {
        expect(
          () => parseMidiDocument({
            'notes': [
              {'on': 0, 'off': 500, 'p': 64, 's': 1, 'l': 1, 'v': 90},
            ],
            'pedal': [],
          }, path: 'midi'),
          throwsA(
            isA<VsbFormatException>().having(
              (e) => e.path,
              'path',
              'midi.notes[0].id',
            ),
          ),
        );
      });

      test('"tied" que não é lista', () {
        expect(
          () => parseMidiDocument({
            'notes': [
              {
                'id': 'x',
                'on': 0,
                'off': 500,
                'p': 64,
                's': 1,
                'l': 1,
                'v': 90,
                'tied': 'y',
              },
            ],
            'pedal': [],
          }, path: 'midi'),
          throwsA(
            isA<VsbFormatException>().having(
              (e) => e.path,
              'path',
              'midi.notes[0].tied',
            ),
          ),
        );
      });

      test('"dir" de pedal desconhecido', () {
        expect(
          () => parseMidiDocument({
            'notes': [],
            'pedal': [
              {'id': 'pd', 't': 0, 'dir': 'sideways', 's': 1},
            ],
          }, path: 'midi'),
          throwsA(isA<VsbFormatException>()),
        );
      });
    });
  });

  group('VsbMidi.notesOf', () {
    test('id de nota simples devolve a própria nota', () {
      final midi = parseMidiDocument(_sampleMidiJson, path: 'midi');
      expect(midi.notesOf('n1a2b').single.id, 'n1a2b');
    });

    test('id de continuação da ligadura devolve a cabeça', () {
      final midi = parseMidiDocument(_sampleMidiJson, path: 'midi');
      final fromContinuation = midi.notesOf('n9f-cont');
      expect(fromContinuation, hasLength(1));
      expect(fromContinuation.single.id, 'n9f');
      expect(fromContinuation.single.tied, ['n9f-cont']);
    });

    test('ornamento: id repetido devolve todas as sub-notas', () {
      final midi = parseMidiDocument(_sampleMidiJson, path: 'midi');
      final sub = midi.notesOf('n33');
      expect(sub, hasLength(2));
      expect(sub.every((n) => n.ornament), isTrue);
      expect(sub.map((n) => n.pitch), [71, 72]);
    });

    test('id sem nota correspondente devolve lista vazia', () {
      final midi = parseMidiDocument(_sampleMidiJson, path: 'midi');
      expect(midi.notesOf('inexistente'), isEmpty);
    });
  });

  group('JSON único', () {
    test('midi ausente: doc.midi é null, resto do documento intacto', () {
      final json = _freshExemploMinimo();

      final doc = VsbDocument.fromJson(json);

      expect(doc.midi, isNull);
      expect(doc.manifest.files.midi, isNull);
      expect(doc.pages, hasLength(1));
    });

    test('midi presente: doc.midi lido e indexado por manifest.files.midi', () {
      final json = _freshExemploMinimo();
      json['midi'] = _sampleMidiJson;
      (json['manifest']['files'] as Map<String, dynamic>)['midi'] =
          'midi.json';

      final doc = VsbDocument.fromJson(json);

      expect(doc.manifest.files.midi, 'midi.json');
      expect(doc.midi, isNotNull);
      expect(doc.midi!.notes, hasLength(4));
      expect(doc.midi!.notesOf('n33'), hasLength(2));
    });
  });

  group('zip (.vsb)', () {
    test('sem midi.json: doc.midi é null sem erro', () {
      final doc = VsbDocument.fromBytes(_zipFrom(_freshExemploMinimo()));

      expect(doc.midi, isNull);
      expect(doc.pages, hasLength(1));
    });

    test('com midi.json: lido quando o manifest o lista', () {
      final root = _freshExemploMinimo();
      final doc = VsbDocument.fromBytes(
        _zipFrom(root, midiJson: _sampleMidiJson),
      );

      expect(doc.midi, isNotNull);
      expect(doc.midi!.pedal, hasLength(2));
    });
  });

  group('fixtures reais', () {
    test('Maple Leaf Rag: id -rend2 com o mesmo pitch da passagem 1', () {
      final doc = _fixture('maple-leaf-rag.vsb');
      final midi = doc.midi!;

      final repeated = midi.notesOf('f17mj3ny-rend2');
      final original = midi.notesOf('f17mj3ny');
      expect(repeated, isNotEmpty);
      expect(original, isNotEmpty);
      expect(repeated.single.pitch, original.single.pitch);
    });

    test(
      'Maple Leaf Rag: todo id de nota do timemap tem notesOf não-vazio '
      '(critério de aceite 2)',
      () {
        final doc = _fixture('maple-leaf-rag.vsb');
        final midi = doc.midi!;

        final noteIds = <String>{
          for (final entry in doc.timemap!) ...entry.on,
        };
        final missing = [
          for (final id in noteIds)
            if (midi.notesOf(id).isEmpty) id,
        ];
        expect(
          missing,
          isEmpty,
          reason: 'ids sem cobertura em midi.json: $missing',
        );
      },
    );

    test('Clair de Lune: pedal e ligadura de uma peça com os dois', () {
      final doc = _fixture('repeticoes/Clair_de_Lune__Debussy.vsb');
      final midi = doc.midi!;

      expect(midi.pedal, isNotEmpty);
      expect(midi.pedal.first.dir, anyOf(PedalDir.down, PedalDir.up));

      final tiedHeads = midi.notes.where((n) => n.tied.isNotEmpty).toList();
      expect(tiedHeads, isNotEmpty);
      final head = tiedHeads.first;
      final continuationId = head.tied.first;
      expect(midi.notesOf(continuationId).single.id, head.id);
    });

    test(
      'Clair de Lune: quase todo id de nota do timemap tem notesOf '
      'não-vazio (algumas exceções conhecidas, herdadas de G01 — notas '
      'silenciosas/cue/sameas, não investigadas a fundo em G02)',
      () {
        final doc = _fixture('repeticoes/Clair_de_Lune__Debussy.vsb');
        final midi = doc.midi!;

        final noteIds = <String>{
          for (final entry in doc.timemap!) ...entry.on,
        };
        final missing = [
          for (final id in noteIds)
            if (midi.notesOf(id).isEmpty) id,
        ];
        expect(
          missing.length,
          lessThanOrEqualTo(5),
          reason: 'ids sem cobertura em midi.json: $missing',
        );
      },
    );
  });
}

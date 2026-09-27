// `meta.json` (§2.3): título e autores da peça, do documento inteiro. Cobre a
// leitura do JSON único e do zip `.vsb`, a ausência do campo e os erros de forma.
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

/// Monta um `.vsb` (zip) em memória a partir do JSON único do exemplo mínimo,
/// separando os documentos como o exportador faz. `meta` (quando não nulo)
/// vira `meta.json`; o manifest só o lista se ele está no zip.
Uint8List _zipFrom(Map<String, dynamic> root, {Object? meta}) {
  final manifest = Map<String, dynamic>.from(root['manifest'] as Map);
  final files = Map<String, dynamic>.from(manifest['files'] as Map);
  if (meta == null) {
    files.remove('meta');
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
  if (meta != null) add('meta.json', meta);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('JSON único: título e créditos do exemplo mínimo', () {
    final doc = VsbDocument.fromJson(_freshExemploMinimo());

    expect(doc.manifest.files.meta, 'meta.json');
    expect(doc.meta, isNotNull);
    expect(doc.meta!.title, 'Título');
    expect(doc.meta!.creators.map((c) => c.name), [
      'Compositor Exemplo',
      'Letrista Exemplo',
    ]);
    expect(doc.meta!.creators.map((c) => c.role), ['composer', 'lyricist']);
  });

  test('composer e creatorWithRole devolvem o primeiro crédito do papel', () {
    final meta = VsbDocument.fromJson(_freshExemploMinimo()).meta!;

    expect(meta.composer, 'Compositor Exemplo');
    expect(meta.creatorWithRole('lyricist'), 'Letrista Exemplo');
    expect(meta.creatorWithRole('arranger'), isNull);
  });

  test('sem meta: doc.meta é null e o manifest não o lista', () {
    final json = _freshExemploMinimo()..remove('meta');
    (json['manifest']['files'] as Map<String, dynamic>).remove('meta');

    final doc = VsbDocument.fromJson(json);

    expect(doc.meta, isNull);
    expect(doc.manifest.files.meta, isNull);
  });

  test('só título, só créditos, e crédito sem papel', () {
    expect(
      parseMetaDocument({'title': 'Só título'}, path: 'meta').creators,
      isEmpty,
    );

    final onlyCreators = parseMetaDocument({
      'creators': [
        {'name': 'Fulano'},
      ],
    }, path: 'meta');
    expect(onlyCreators.title, isNull);
    expect(onlyCreators.creators.single.name, 'Fulano');
    expect(onlyCreators.creators.single.role, isNull);
    expect(onlyCreators.composer, isNull);
  });

  test('chaves desconhecidas em meta são ignoradas', () {
    final meta = parseMetaDocument({
      'title': 'X',
      'opus': 'op. 1',
      'creators': [
        {'name': 'Y', 'role': 'composer', 'born': 1800},
      ],
    }, path: 'meta');

    expect(meta.title, 'X');
    expect(meta.composer, 'Y');
  });

  test('zip: meta.json é lido quando o manifest o lista', () {
    final root = _freshExemploMinimo();
    final doc = VsbDocument.fromBytes(_zipFrom(root, meta: root['meta']));

    expect(doc.meta!.title, 'Título');
    expect(doc.meta!.composer, 'Compositor Exemplo');
  });

  test('zip sem meta.json: doc.meta é null', () {
    final doc = VsbDocument.fromBytes(_zipFrom(_freshExemploMinimo()));

    expect(doc.meta, isNull);
    expect(doc.pages, hasLength(1));
  });

  group('erros de forma', () {
    test('title que não é string', () {
      expect(
        () => parseMetaDocument({'title': 7}, path: 'meta'),
        throwsA(isA<VsbFormatException>()),
      );
    });

    test('creators que não é lista', () {
      expect(
        () => parseMetaDocument({'creators': 'Fulano'}, path: 'meta'),
        throwsA(
          isA<VsbFormatException>().having(
            (e) => e.path,
            'path',
            'meta.creators',
          ),
        ),
      );
    });

    test('crédito sem name', () {
      expect(
        () => parseMetaDocument({
          'creators': [
            {'role': 'composer'},
          ],
        }, path: 'meta'),
        throwsA(
          isA<VsbFormatException>().having(
            (e) => e.path,
            'path',
            contains('meta.creators[0]'),
          ),
        ),
      );
    });
  });
}

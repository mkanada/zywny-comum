import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_library/library_envelope.dart';
import 'package:zywny_library/library_package.dart';

const _xml = '<score-partwise version="4.0"><part-list/></score-partwise>';

Map<String, dynamic> _manifest([Map<String, dynamic> over = const {}]) => {
  'formato': 1,
  'id': 'hinos',
  'nome': 'Hinário',
  'versao': '2026.10.04',
  'termo': {'singular': 'hino', 'plural': 'hinos', 'genero': 'm'},
  'numerada': true,
  'creditos': 'Teste.',
  'idioma': 'pt-BR',
  ...over,
};

Map<String, dynamic> _entry(String id, {int? n, Map<String, dynamic>? over}) =>
    {
      'id': id,
      'n': ?n,
      't': 'Título $id',
      'c': 'Compositor',
      'k': 'titulo $id',
      'ck': 'compositor',
      'q': 'titulo $id compositor',
      ...?over,
    };

/// Monta um `.zywny` em memória. Passe `null` em [manifest] ou [index] para
/// omitir o arquivo, e uma lista em [scores] para escolher as partituras.
Uint8List _zip({
  Object? manifest = const {},
  Object? index = const [],
  List<String>? scores,
  bool store = false,
}) {
  final archive = Archive();
  void add(String name, List<int> data) {
    final f = ArchiveFile.bytes(name, data);
    if (store) f.compression = CompressionType.none;
    archive.add(f);
  }

  if (manifest != null) {
    add(
      'manifest.json',
      utf8.encode(
        jsonEncode(
          manifest is Map && manifest.isEmpty ? _manifest() : manifest,
        ),
      ),
    );
  }
  final list = index is List && index.isEmpty
      ? [_entry('001', n: 1), _entry('002', n: 2)]
      : index;
  if (list != null) add('indice.json', utf8.encode(jsonEncode(list)));
  final ids = scores ?? ['001', '002'];
  for (final id in ids) {
    add('partituras/$id.musicxml.gz', GZipEncoder().encode(utf8.encode(_xml)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _expectError(Uint8List bytes, Matcher message) {
  expect(
    () => LibraryPackage.parse(bytes),
    throwsA(
      isA<LibraryFormatException>().having(
        (e) => e.message,
        'message',
        message,
      ),
    ),
  );
}

void main() {
  group('LibraryPackage.parse', () {
    test('pacote válido: manifesto, índice e partitura', () async {
      final pkg = LibraryPackage.parse(_zip());
      expect(pkg.manifest.id, 'hinos');
      expect(pkg.manifest.name, 'Hinário');
      expect(pkg.manifest.version, '2026.10.04');
      expect(pkg.manifest.numbered, isTrue);
      expect(pkg.manifest.term.singular, 'hino');
      expect(pkg.manifest.term.plural, 'hinos');
      expect(pkg.manifest.term.feminine, isFalse);
      expect(pkg.manifest.credits, 'Teste.');
      expect(pkg.manifest.language, 'pt-BR');
      expect(pkg.pieces.map((p) => p.id), ['001', '002']);
      expect(pkg.pieces.map((p) => p.number), [1, 2]);
      expect(pkg.pieces.first.title, 'Título 001');
      expect(utf8.decode(await pkg.loadScore('002')), _xml);
    });

    test('zip sem compressão (store) também lê', () async {
      final pkg = LibraryPackage.parse(_zip(store: true));
      expect(utf8.decode(await pkg.loadScore('001')), _xml);
    });

    test('biblioteca não numerada: n some e o termo é feminino', () {
      final pkg = LibraryPackage.parse(
        _zip(
          manifest: _manifest({
            'id': 'classicos',
            'numerada': false,
            'termo': {'singular': 'peça', 'plural': 'peças', 'genero': 'f'},
          }),
          index: [
            _entry('bwv-114', over: {'o': 'BWV Anh. 114'}),
            _entry('op100-2'),
          ],
          scores: ['bwv-114', 'op100-2'],
        ),
      );
      expect(pkg.manifest.numbered, isFalse);
      expect(pkg.manifest.term.feminine, isTrue);
      expect(pkg.pieces.map((p) => p.id), ['bwv-114', 'op100-2']);
      expect(pkg.pieces.first.originalTitle, 'BWV Anh. 114');
    });

    test('campos opcionais do índice chegam à peça', () {
      final pkg = LibraryPackage.parse(
        _zip(
          index: [
            _entry(
              '001',
              n: 1,
              over: {'l': 'Letrista', 'nv': 3, 'd': 41.5, 'a': -2},
            ),
          ],
          scores: ['001'],
        ),
      );
      final p = pkg.pieces.single;
      expect(p.lyricist, 'Letrista');
      expect(p.level, 3);
      expect(p.difficulty, 41.5);
      expect(p.fifths, -2);
    });

    test('loadScore de id desconhecido falha', () {
      final pkg = LibraryPackage.parse(_zip());
      expect(pkg.loadScore('999'), throwsArgumentError);
    });

    group('erros', () {
      test('não é zip', () {
        _expectError(
          Uint8List.fromList(utf8.encode('isto não é um zip')),
          contains('não é um .zip válido'),
        );
      });

      test('falta manifest.json', () {
        _expectError(_zip(manifest: null), contains('"manifest.json"'));
      });

      test('falta indice.json', () {
        _expectError(_zip(index: null), contains('"indice.json"'));
      });

      test('manifesto com JSON inválido', () {
        final archive = Archive()
          ..add(ArchiveFile.bytes('manifest.json', utf8.encode('{ nope')))
          ..add(ArchiveFile.bytes('indice.json', utf8.encode('[]')));
        _expectError(
          Uint8List.fromList(ZipEncoder().encode(archive)),
          contains('JSON inválido'),
        );
      });

      test('formato mais novo que o app', () {
        _expectError(
          _zip(manifest: _manifest({'formato': 2})),
          contains('versão mais nova do zywny'),
        );
      });

      test('formato ausente', () {
        _expectError(
          _zip(manifest: _manifest()..remove('formato')),
          contains('"formato"'),
        );
      });

      test('id da biblioteca inválido', () {
        _expectError(
          _zip(manifest: _manifest({'id': 'Hinos Bons'})),
          contains('"id" da biblioteca é inválido'),
        );
      });

      test('manifesto sem nome', () {
        _expectError(
          _zip(manifest: _manifest()..remove('nome')),
          contains('"nome"'),
        );
      });

      test('manifesto sem termo', () {
        _expectError(
          _zip(manifest: _manifest()..remove('termo')),
          contains('"termo"'),
        );
      });

      test('termo com gênero inválido', () {
        _expectError(
          _zip(
            manifest: _manifest({
              'termo': {'singular': 'a', 'plural': 'as', 'genero': 'x'},
            }),
          ),
          contains('"genero"'),
        );
      });

      test('indice.json que não é lista', () {
        _expectError(_zip(index: {'a': 1}), contains('lista de músicas'));
      });

      test('id de peça inválido', () {
        _expectError(
          _zip(index: [_entry('a b', n: 1)], scores: ['a b']),
          contains('"id" inválido'),
        );
      });

      test('id de peça ausente', () {
        final e = _entry('001', n: 1)..remove('id');
        _expectError(_zip(index: [e], scores: []), contains('"id" inválido'));
      });

      test('id de peça repetido', () {
        _expectError(
          _zip(index: [_entry('001', n: 1), _entry('001', n: 2)]),
          contains('"001" aparece mais de uma vez'),
        );
      });

      test('peça no índice sem partitura', () {
        _expectError(
          _zip(
            index: [_entry('001', n: 1), _entry('002', n: 2)],
            scores: ['001'],
          ),
          contains('"002" está no índice mas não tem partitura'),
        );
      });

      test('numerada sem n', () {
        _expectError(
          _zip(index: [_entry('001'), _entry('002', n: 2)]),
          contains('"001" não tem número'),
        );
      });

      test('n repetido', () {
        _expectError(
          _zip(index: [_entry('001', n: 7), _entry('002', n: 7)]),
          contains('número 7 aparece em mais de uma'),
        );
      });

      test('campo obrigatório do índice faltando', () {
        final e = _entry('001', n: 1)..remove('q');
        _expectError(
          _zip(index: [e], scores: ['001']),
          contains('"001" não tem o campo obrigatório "q"'),
        );
      });
    });
  });

  // O pacote real, gerado por `just pacote-hinos` (não versionado): sem ele
  // o teste se pula.
  final real = File('../../dist/hinos.zywny');
  group('dist/hinos.zywny', () {
    test(
      'lê sem erro, rápido, e bate com o índice embutido',
      () async {
        final bytes = real.readAsBytesSync();
        // O arquivo é um envelope cifrado e assinado; o zip de dentro é o que
        // o `LibraryPackage` lê (o envelope em si é do library_envelope_test).
        final pub = Uint8List.fromList(
          base64.decode(
            File('../../keys/biblioteca.public.b64').readAsStringSync().trim(),
          ),
        );
        final zip = await LibraryEnvelope.open(bytes, pub);
        final watch = Stopwatch()..start();
        final pkg = LibraryPackage.parse(zip);
        watch.stop();
        // ignore: avoid_print
        print(
          'parse de ${pkg.pieces.length} peças / '
          '${(bytes.length / 1e6).toStringAsFixed(1)} MB: '
          '${watch.elapsedMilliseconds} ms',
        );
        expect(pkg.manifest.id, 'hinos');
        expect(pkg.manifest.numbered, isTrue);
        expect(pkg.pieces, hasLength(600));
        expect(watch.elapsedMilliseconds, lessThan(300));

        final xml = utf8.decode(await pkg.loadScore('001'));
        expect(xml, contains('<score-partwise'));
      },
      skip:
          real.existsSync() &&
              File('../../keys/biblioteca.public.b64').existsSync()
          ? false
          : 'rode `just pacote-hinos`',
    );
  });
}

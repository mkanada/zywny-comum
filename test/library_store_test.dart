import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_library/library_blob_store.dart';
import 'package:zywny_library/library_blob_store_native.dart';
import 'package:zywny_library/library_envelope.dart';
import 'package:zywny_library/library_package.dart';
import 'package:zywny_library/library_store.dart';

import 'support/library_fixtures.dart';

void main() {
  late TestKeys keys;
  late Uint8List pub;
  setUpAll(() async {
    keys = await TestKeys.generate();
    pub = keys.pub;
  });

  Future<Uint8List> makePackage(
    String id, {
    String name = 'Biblioteca',
    String version = '1',
    int pieces = 2,
    Uint8List? seed,
  }) => keys.package(
    id,
    name: name,
    version: version,
    pieces: pieces,
    signWith: seed,
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  LibraryStore make(LibraryBlobStore blobs, {Uint8List? key}) => LibraryStore(
    blobs: blobs,
    prefs: SharedPreferencesAsync(),
    publicKey: key ?? pub,
  );

  group('LibraryStore (em memória)', () {
    test('começa vazio', () async {
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      expect(store.installed, isEmpty);
      expect(store.activeId, isNull);
      expect(store.active, isNull);
    });

    test('instalar: lista, vira a em uso e abre o pacote', () async {
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      var notified = 0;
      store.addListener(() => notified++);
      final lib = await store.install(
        await makePackage('hinos', name: 'Hinário', version: '2026.10.04'),
      );
      expect(lib.id, 'hinos');
      expect(lib.name, 'Hinário');
      expect(lib.pieceCount, 2);
      expect(store.installed.map((e) => e.id), ['hinos']);
      expect(store.activeId, 'hinos');
      expect(notified, greaterThan(0));
      final pkg = await store.open('hinos');
      expect(pkg!.pieces, hasLength(2));
      expect(await store.open('outra'), isNull);
    });

    test('a nova instalada vira a em uso; activate:false mantém', () async {
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      await store.install(await makePackage('hinos'));
      await store.install(await makePackage('classicos'));
      expect(store.activeId, 'classicos');
      await store.install(await makePackage('extra'), activate: false);
      expect(store.activeId, 'classicos');
      expect(store.installed.map((e) => e.id), ['hinos', 'classicos', 'extra']);
    });

    test('mesmo id substitui no lugar, com a versão nova', () async {
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      await store.install(await makePackage('hinos', version: '1', pieces: 2));
      await store.install(await makePackage('classicos'));
      await store.install(await makePackage('hinos', version: '2', pieces: 3));
      expect(store.installed.map((e) => e.id), ['hinos', 'classicos']);
      expect(store['hinos']!.version, '2');
      expect(store['hinos']!.pieceCount, 3);
    });

    test('pacote inválido não grava nada', () async {
      final blobs = MemoryLibraryBlobStore();
      final store = make(blobs);
      await store.load();
      await store.install(await makePackage('hinos'));
      final other = Uint8List.fromList(
        List.generate(32, (i) => i + 1),
      ); // outra privada
      await expectLater(
        store.install(await makePackage('forjada', seed: other)),
        throwsA(isA<LibraryFormatException>()),
      );
      await expectLater(
        store.install(Uint8List.fromList(utf8.encode('lixo'))),
        throwsA(isA<LibraryFormatException>()),
      );
      expect(blobs.blobs.keys, ['hinos']);
      expect(store.installed.map((e) => e.id), ['hinos']);
      expect(store.activeId, 'hinos');
    });

    test('app sem chave recusa instalar, com mensagem', () async {
      final store = LibraryStore(
        blobs: MemoryLibraryBlobStore(),
        prefs: SharedPreferencesAsync(),
      );
      await store.load();
      await expectLater(
        store.install(await makePackage('hinos')),
        throwsA(
          isA<LibraryFormatException>().having(
            (e) => e.message,
            'message',
            contains('sem a chave'),
          ),
        ),
      );
    });

    test(
      'remover a em uso passa para a primeira restante, depois nenhuma',
      () async {
        final blobs = MemoryLibraryBlobStore();
        final store = make(blobs);
        await store.load();
        await store.install(await makePackage('a'));
        await store.install(await makePackage('b'));
        await store.install(await makePackage('c'));
        expect(store.activeId, 'c');
        await store.remove('c');
        expect(store.activeId, 'a');
        expect(blobs.blobs.keys, unorderedEquals(['a', 'b']));
        await store.remove('b'); // não é a em uso
        expect(store.activeId, 'a');
        await store.remove('a');
        expect(store.activeId, isNull);
        expect(store.installed, isEmpty);
        await store.remove('a'); // já removida: nada acontece
      },
    );

    test('remover guarda o progresso (as chaves de preferências)', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('lib_progress_hinos', '{"001":{"s":90}}');
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      await store.install(await makePackage('hinos'));
      await store.remove('hinos');
      expect(await prefs.getString('lib_progress_hinos'), isNotNull);
    });

    test('setActive troca; id desconhecido é erro', () async {
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      await store.install(await makePackage('a'));
      await store.install(await makePackage('b'));
      await store.setActive('a');
      expect(store.activeId, 'a');
      expect(() => store.setActive('zzz'), throwsArgumentError);
    });

    test('recarregar: lista e em uso voltam das preferências', () async {
      final blobs = MemoryLibraryBlobStore();
      final first = make(blobs);
      await first.load();
      await first.install(await makePackage('a'));
      await first.install(await makePackage('b'));
      await first.setActive('a');

      final second = make(blobs);
      await second.load();
      expect(second.installed.map((e) => e.id), ['a', 'b']);
      expect(second.activeId, 'a');
      expect(second['b']!.term.plural, 'hinos');
    });

    test(
      'pacote sumido do disco sai da lista; em uso cai na primeira',
      () async {
        final blobs = MemoryLibraryBlobStore();
        final first = make(blobs);
        await first.load();
        await first.install(await makePackage('a'));
        await first.install(await makePackage('b'));
        await blobs.delete('b'); // a em uso

        final second = make(blobs);
        await second.load();
        expect(second.installed.map((e) => e.id), ['a']);
        expect(second.activeId, 'a');
      },
    );

    test('lista estragada nas preferências: recomeça vazia', () async {
      await SharedPreferencesAsync().setString(
        LibraryStore.installedKey,
        '{ não é json',
      );
      final store = make(MemoryLibraryBlobStore());
      await store.load();
      expect(store.installed, isEmpty);
    });

    test('o que fica guardado é o envelope, não o zip', () async {
      final blobs = MemoryLibraryBlobStore();
      final store = make(blobs);
      await store.load();
      final bytes = await makePackage('hinos');
      await store.install(bytes);
      expect(blobs.blobs['hinos'], bytes);
      expect(LibraryEnvelope.looksSealed((await store.read('hinos'))!), isTrue);
    });
  });

  group('FileLibraryBlobStore', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('zywny_bib_');
    });
    tearDown(() => dir.delete(recursive: true));

    FileLibraryBlobStore files() => FileLibraryBlobStore(
      directory: () async => Directory('${dir.path}/bibliotecas'),
    );

    test('put, get, contains, delete; cria a pasta', () async {
      final blobs = files();
      expect(await blobs.contains('a'), isFalse);
      expect(await blobs.get('a'), isNull);
      await blobs.put('a', Uint8List.fromList([1, 2, 3]));
      expect(await blobs.contains('a'), isTrue);
      expect(await blobs.get('a'), [1, 2, 3]);
      await blobs.put('a', Uint8List.fromList([9]));
      expect(await blobs.get('a'), [9]);
      await blobs.delete('a');
      expect(await blobs.contains('a'), isFalse);
      await blobs.delete('a'); // de novo: sem erro
    });

    test('não deixa temporário para trás', () async {
      final blobs = files();
      await blobs.put('a', Uint8List.fromList([1]));
      final names = Directory('${dir.path}/bibliotecas')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(names, ['a.zywny']);
    });

    test('o store reinicia e continua com as bibliotecas', () async {
      final first = make(files());
      await first.load();
      await first.install(await makePackage('hinos'));

      final second = make(files());
      await second.load();
      expect(second.activeId, 'hinos');
      expect((await second.open('hinos'))!.pieces, hasLength(2));
    });
  });

  // O pacote real do gerador (`just pacote-hinos`) instalado em arquivo e
  // relido por um store novo, como depois de reiniciar o app.
  final real = File('dist/hinos.zywny');
  final publicFile = File('keys/biblioteca.public.b64');
  test(
    'dist/hinos.zywny instala em arquivo e continua lá no próximo store',
    () async {
      final dir = await Directory.systemTemp.createTemp('zywny_bib_real_');
      addTearDown(() => dir.delete(recursive: true));
      final pub = Uint8List.fromList(
        base64.decode(publicFile.readAsStringSync().trim()),
      );
      FileLibraryBlobStore files() =>
          FileLibraryBlobStore(directory: () async => dir);
      final first = make(files(), key: pub);
      await first.load();
      final lib = await first.install(real.readAsBytesSync());
      expect(lib.pieceCount, 600);

      final second = make(files(), key: pub);
      await second.load();
      expect(second.activeId, 'hinos');
      final pkg = await second.open('hinos');
      expect(pkg!.pieces, hasLength(600));
      expect(
        utf8.decode(await pkg.loadScore('001')),
        contains('<score-partwise'),
      );
    },
    skip: real.existsSync() && publicFile.existsSync()
        ? false
        : 'rode `tool/library_crypto.py gen` e `just pacote-hinos`',
  );
}

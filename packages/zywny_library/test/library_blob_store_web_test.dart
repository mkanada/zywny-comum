@TestOn('browser')
library;

// IndexedDB de verdade: roda no navegador, `flutter test --platform chrome
// test/library_blob_store_web_test.dart` (B03). Fora do `just test` comum.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_library/library_envelope.dart';
import 'package:zywny_library/library_package.dart';
import 'package:zywny_library/library_blob_store_web.dart';

void main() {
  // Um banco por execução, para não herdar o que a anterior deixou.
  final db = 'zywny_teste_${DateTime.now().microsecondsSinceEpoch}';

  test('put, get, contains, delete', () async {
    final blobs = IndexedDbLibraryBlobStore(dbName: db);
    expect(await blobs.contains('a'), isFalse);
    expect(await blobs.get('a'), isNull);
    await blobs.put('a', Uint8List.fromList([1, 2, 3]));
    expect(await blobs.contains('a'), isTrue);
    expect(await blobs.get('a'), [1, 2, 3]);
    await blobs.put('a', Uint8List.fromList([9]));
    expect(await blobs.get('a'), [9]);
    await blobs.delete('a');
    expect(await blobs.contains('a'), isFalse);
    await blobs.delete('a');
  });

  test(
    'outra conexão (como depois de recarregar) vê o que foi gravado',
    () async {
      await IndexedDbLibraryBlobStore(
        dbName: db,
      ).put('b', Uint8List.fromList(List.generate(4 * 1024 * 1024, (i) => i)));
      final again = IndexedDbLibraryBlobStore(dbName: db);
      final bytes = await again.get('b');
      expect(bytes, hasLength(4 * 1024 * 1024));
      expect(bytes![1000], 1000 % 256);
      await again.delete('b');
    },
  );

  // O envelope no navegador (WebCrypto no lugar do Dart puro): assina, cifra e
  // abre; adulterado ou com outra chave é recusado.
  test('envelope: seal e open no navegador', () async {
    final pair = await Ed25519().newKeyPair();
    final seed = Uint8List.fromList(await pair.extractPrivateKeyBytes());
    final pub = Uint8List.fromList((await pair.extractPublicKey()).bytes);
    final zip = Uint8List.fromList(
      List.generate(3 * 1024 * 1024, (i) => i * 7),
    );
    final watch = Stopwatch()..start();
    final sealed = await LibraryEnvelope.seal(
      zip,
      privateSeed: seed,
      publicKey: pub,
    );
    final back = await LibraryEnvelope.open(sealed, pub);
    // ignore: avoid_print
    print('seal+open de 3 MB no navegador: ${watch.elapsedMilliseconds} ms');
    expect(back, zip);
    final bad = Uint8List.fromList(sealed)..[100] ^= 1;
    expect(
      LibraryEnvelope.open(bad, pub),
      throwsA(isA<LibraryFormatException>()),
    );
  });
}

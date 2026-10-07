import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_library/library_envelope.dart';
import 'package:zywny_library/library_package.dart';

Uint8List _zip() {
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(
        'manifest.json',
        utf8.encode(
          jsonEncode({
            'formato': 1,
            'id': 'teste',
            'nome': 'Teste',
            'versao': '1',
            'termo': {'singular': 'peça', 'plural': 'peças', 'genero': 'f'},
            'numerada': false,
          }),
        ),
      ),
    )
    ..add(ArchiveFile.bytes('indice.json', utf8.encode('[]')));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<({Uint8List seed, Uint8List pub})> _keys() async {
  final pair = await Ed25519().newKeyPair();
  final data = await pair.extract();
  return (
    seed: Uint8List.fromList(await pair.extractPrivateKeyBytes()),
    pub: Uint8List.fromList(data.publicKey.bytes),
  );
}

Future<void> _expectRejected(Future<Object?> f, Matcher message) => expectLater(
  f,
  throwsA(
    isA<LibraryFormatException>().having((e) => e.message, 'message', message),
  ),
);

void main() {
  test(
    'seal e open: o zip volta igual e o conteúdo não aparece no envelope',
    () async {
      final k = await _keys();
      final zip = _zip();
      final sealed = await LibraryEnvelope.seal(
        zip,
        privateSeed: k.seed,
        publicKey: k.pub,
      );
      expect(LibraryEnvelope.looksSealed(sealed), isTrue);
      expect(String.fromCharCodes(sealed), isNot(contains('manifest.json')));
      expect(await LibraryEnvelope.open(sealed, k.pub), zip);
      final pkg = await openLibraryPackage(sealed, k.pub);
      expect(pkg.manifest.id, 'teste');
    },
  );

  test('sal e nonce aleatórios: dois envelopes do mesmo zip diferem', () async {
    final k = await _keys();
    final a = await LibraryEnvelope.seal(
      _zip(),
      privateSeed: k.seed,
      publicKey: k.pub,
    );
    final b = await LibraryEnvelope.seal(
      _zip(),
      privateSeed: k.seed,
      publicKey: k.pub,
    );
    expect(a, isNot(b));
  });

  group('rejeita', () {
    late ({Uint8List seed, Uint8List pub}) k;
    late Uint8List sealed;
    setUp(() async {
      k = await _keys();
      sealed = await LibraryEnvelope.seal(
        _zip(),
        privateSeed: k.seed,
        publicKey: k.pub,
      );
    });

    test('assinado por outra chave', () async {
      final other = await _keys();
      await _expectRejected(
        LibraryEnvelope.open(sealed, other.pub),
        contains('não foi assinada pela chave deste app'),
      );
    });

    test('pacote assinado por outra chave privada, mesmo com a pública certa a cifrar', () async {
      final other = await _keys();
      // Quem não tem a privada não consegue forjar: assina com a sua.
      final forged = await LibraryEnvelope.seal(
        _zip(),
        privateSeed: other.seed,
        publicKey: k.pub,
      );
      await _expectRejected(
        LibraryEnvelope.open(forged, k.pub),
        contains('não foi assinada'),
      );
    });

    test('um byte alterado na cifra', () async {
      final bad = Uint8List.fromList(sealed)..[60] ^= 0x01;
      await _expectRejected(
        LibraryEnvelope.open(bad, k.pub),
        contains('não foi assinada'),
      );
    });

    test('cabeçalho alterado', () async {
      final bad = Uint8List.fromList(sealed)..[10] ^= 0x01;
      await _expectRejected(
        LibraryEnvelope.open(bad, k.pub),
        contains('não foi assinada'),
      );
    });

    test('truncado', () async {
      await _expectRejected(
        LibraryEnvelope.open(Uint8List.sublistView(sealed, 0, 40), k.pub),
        contains('não é uma biblioteca do zywny'),
      );
    });

    test('um zip sem cifra', () async {
      final zip = _zip();
      expect(LibraryEnvelope.looksSealed(zip), isFalse);
      await _expectRejected(
        LibraryEnvelope.open(zip, k.pub),
        contains('não é uma biblioteca do zywny'),
      );
    });

    test('versão do envelope mais nova', () async {
      final bad = Uint8List.fromList(sealed)..[4] = 2;
      await _expectRejected(
        LibraryEnvelope.open(bad, k.pub),
        contains('versão mais nova do zywny'),
      );
    });
  });

  // O pacote real do gerador Python (`just pacote-hinos`) com o par de
  // `keys/` (não versionado): prova que Python e Dart falam o mesmo envelope.
  final real = File('../../dist/hinos.zywny');
  final publicFile = File('../../keys/biblioteca.public.b64');
  test(
    'dist/hinos.zywny do gerador Python abre no Dart',
    () async {
      final bytes = real.readAsBytesSync();
      final pub = Uint8List.fromList(
        base64.decode(publicFile.readAsStringSync().trim()),
      );
      final watch = Stopwatch()..start();
      final pkg = await openLibraryPackage(bytes, pub);
      watch.stop();
      // ignore: avoid_print
      print(
        'abrir ${pkg.pieces.length} peças / '
        '${(bytes.length / 1e6).toStringAsFixed(1)} MB (assinatura + decifrar '
        '+ parse): ${watch.elapsedMilliseconds} ms',
      );
      expect(pkg.manifest.id, 'hinos');
      expect(pkg.pieces, hasLength(600));
    },
    skip: real.existsSync() && publicFile.existsSync()
        ? false
        : 'rode `tool/library_crypto.py gen` e `just pacote-hinos`',
  );
}

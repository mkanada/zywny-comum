import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:zywny_library/library_envelope.dart';

/// Um par de chaves Ed25519 de teste (nunca as de `keys/`).
class TestKeys {
  TestKeys(this.seed, this.pub);

  static Future<TestKeys> generate() async {
    final pair = await Ed25519().newKeyPair();
    return TestKeys(
      Uint8List.fromList(await pair.extractPrivateKeyBytes()),
      Uint8List.fromList((await pair.extractPublicKey()).bytes),
    );
  }

  final Uint8List seed;
  final Uint8List pub;

  /// Um `.zywny` de teste (zip em memória, cifrado e assinado), com [pieces]
  /// músicas de id `1..n`, número `n` e uma partitura mínima.
  Future<Uint8List> package(
    String id, {
    String name = 'Biblioteca',
    String version = '1',
    int pieces = 2,
    bool numbered = true,
    String singular = 'hino',
    String plural = 'hinos',
    bool feminine = false,
    Uint8List? signWith,
  }) async {
    final index = [
      for (var i = 1; i <= pieces; i++)
        {
          'id': '$i',
          if (numbered) 'n': i,
          't': 'T$i',
          'c': 'C',
          if (!numbered) 'o': 'Op. $i',
          'k': 't$i',
          'ck': 'c',
          'q': 't$i c',
        },
    ];
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'manifest.json',
          utf8.encode(
            jsonEncode({
              'formato': 1,
              'id': id,
              'nome': name,
              'versao': version,
              'termo': {
                'singular': singular,
                'plural': plural,
                'genero': feminine ? 'f' : 'm',
              },
              'numerada': numbered,
              'creditos': 'Créditos do teste.',
            }),
          ),
        ),
      )
      ..add(ArchiveFile.bytes('indice.json', utf8.encode(jsonEncode(index))));
    for (var i = 1; i <= pieces; i++) {
      archive.add(
        ArchiveFile.bytes(
          'partituras/$i.musicxml.gz',
          GZipEncoder().encode(utf8.encode('<score-partwise id="$i"/>')),
        ),
      );
    }
    return LibraryEnvelope.seal(
      Uint8List.fromList(ZipEncoder().encode(archive)),
      privateSeed: signWith ?? seed,
      publicKey: pub,
    );
  }
}

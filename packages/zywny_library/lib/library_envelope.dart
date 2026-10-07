import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'library_package.dart';

/// Chave pública (Ed25519, 32 bytes) das bibliotecas, entrada no build por
/// `--dart-define=ZYWNY_LIBRARY_KEY=<base64>` (ver `just` e docs/plano/B00).
/// Vazia num app compilado sem chave: nenhuma biblioteca instala.
const _kLibraryKeyDefine = String.fromEnvironment('ZYWNY_LIBRARY_KEY');

/// A chave embutida no build, ou `null` se o app foi compilado sem ela.
Uint8List? libraryKeyFromEnvironment() => _kLibraryKeyDefine.isEmpty
    ? null
    : Uint8List.fromList(base64.decode(_kLibraryKeyDefine.trim()));

const _magic = [0x5A, 0x59, 0x57, 0x4E]; // "ZYWN"
const _version = 1;
const _saltLength = 32;
const _nonceLength = 12;
const _tagLength = 16;
const _signatureLength = 64;
const _headerLength = 4 + 1 + _saltLength + _nonceLength;
const _hkdfInfo = 'zywny-library-v1';

/// O envelope em volta do zip do `.zywny` (D-BIB-CIFRA):
///
/// ```
/// "ZYWN" | versão(1) | sal(32) | nonce(12) | cifra+tag(AES-256-GCM) | assinatura(64)
/// ```
///
/// - A **chave privada** (Ed25519) só existe com quem gera o pacote: ela
///   assina cabeçalho + cifra. O app só instala o que foi assinado por ela.
/// - O zip vai cifrado com AES-256-GCM; a chave de conteúdo sai de
///   `HKDF-SHA256(chave pública, sal)`. Quem tem só o arquivo não lê as
///   partituras; quem tem a chave pública (o app, e você) lê. A chave pública
///   fica fora do git e é embutida no build.
class LibraryEnvelope {
  const LibraryEnvelope._();

  static final _ed25519 = Ed25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// `true` se [bytes] começa como um envelope (para dar uma mensagem melhor
  /// a quem abre um zip velho, sem cifra).
  static bool looksSealed(Uint8List bytes) =>
      bytes.length >= _magic.length && _hasMagic(bytes);

  /// Confere a assinatura e decifra; devolve os bytes do zip. Qualquer falha
  /// vira uma [LibraryFormatException] — nada é devolvido pela metade.
  static Future<Uint8List> open(Uint8List bytes, Uint8List publicKey) async {
    const notValid = LibraryFormatException(
      'Este arquivo não é uma biblioteca do zywny (ou está corrompido).',
    );
    if (bytes.length < _headerLength + _tagLength + _signatureLength ||
        !_hasMagic(bytes)) {
      throw notValid;
    }
    if (bytes[4] > _version) {
      throw const LibraryFormatException(
        'Esta biblioteca pede uma versão mais nova do zywny.',
      );
    }
    if (bytes[4] != _version) throw notValid;

    final signedEnd = bytes.length - _signatureLength;
    final signed = Uint8List.sublistView(bytes, 0, signedEnd);
    final signature = Uint8List.sublistView(bytes, signedEnd);
    final ok = await _ed25519.verify(
      signed,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) {
      throw const LibraryFormatException(
        'Esta biblioteca não foi assinada pela chave deste app: '
        'não vou instalar.',
      );
    }

    final salt = Uint8List.sublistView(bytes, 5, 5 + _saltLength);
    final nonce = Uint8List.sublistView(bytes, 5 + _saltLength, _headerLength);
    final tagStart = signedEnd - _tagLength;
    try {
      final key = await _contentKey(publicKey, salt);
      final plain = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(bytes, _headerLength, tagStart),
          nonce: nonce,
          mac: Mac(Uint8List.sublistView(bytes, tagStart, signedEnd)),
        ),
        secretKey: key,
        aad: Uint8List.sublistView(bytes, 0, _headerLength),
      );
      return Uint8List.fromList(plain);
    } on Object {
      throw notValid;
    }
  }

  /// Cifra e assina [zip] — o que `tool/library_crypto.py` faz no gerador.
  /// Em Dart só os testes precisam; [salt] e [nonce] existem para eles.
  static Future<Uint8List> seal(
    Uint8List zip, {
    required Uint8List privateSeed,
    required Uint8List publicKey,
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    final s =
        salt ??
        Uint8List.fromList(SecretKeyData.random(length: _saltLength).bytes);
    final n = nonce ?? Uint8List.fromList(_aes.newNonce());
    final header = Uint8List.fromList([..._magic, _version, ...s, ...n]);
    final box = await _aes.encrypt(
      zip,
      secretKey: await _contentKey(publicKey, s),
      nonce: n,
      aad: header,
    );
    final body = Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    final pair = await _ed25519.newKeyPairFromSeed(privateSeed);
    final signature = await _ed25519.sign(body, keyPair: pair);
    return Uint8List.fromList([...body, ...signature.bytes]);
  }

  static bool _hasMagic(Uint8List bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<SecretKey> _contentKey(Uint8List publicKey, Uint8List salt) =>
      _hkdf.deriveKey(
        secretKey: SecretKey(publicKey),
        nonce: salt,
        info: utf8.encode(_hkdfInfo),
      );
}

/// Abre um `.zywny` como chega do seletor de arquivos: confere a assinatura,
/// decifra e valida o conteúdo.
Future<LibraryPackage> openLibraryPackage(
  Uint8List sealed,
  Uint8List publicKey,
) async => LibraryPackage.parse(await LibraryEnvelope.open(sealed, publicKey));

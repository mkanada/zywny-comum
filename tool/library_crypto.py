#!/usr/bin/env python3
"""Chaves e envelope dos pacotes `.zywny` (D-BIB-CIFRA, docs/plano/B00).

O envelope (igual ao de `lib/library/library_envelope.dart`):

    "ZYWN" | versão(1) | sal(32) | nonce(12) | cifra+tag(AES-256-GCM) | assinatura(64)

A chave privada (Ed25519) assina; a chave de conteúdo sai de
HKDF-SHA256(chave pública, sal). As chaves moram em `keys/` (fora do git,
nunca vão para o remoto) em base64, uma por arquivo.

    tool/library_crypto.py gen [PASTA]      gera o par (não sobrescreve)
    tool/library_crypto.py open ARQ.zywny   decifra e confere (para depurar)
"""

import base64
import os
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

PROJ = Path(__file__).resolve().parent.parent
KEYS = PROJ / "keys"
PRIVATE = "biblioteca.private.b64"
PUBLIC = "biblioteca.public.b64"
MAGIC = b"ZYWN"
VERSION = 1
INFO = b"zywny-library-v1"
HEADER = len(MAGIC) + 1 + 32 + 12


def _raw_private(key: Ed25519PrivateKey) -> bytes:
    return key.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )


def _raw_public(key: Ed25519PublicKey) -> bytes:
    return key.public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )


def generate_keys(folder: Path = KEYS) -> tuple[Path, Path]:
    """Cria o par em [folder]; recusa sobrescrever (perder a privada é
    perder a capacidade de gerar bibliotecas que os apps instalados aceitem)."""
    priv, pub = folder / PRIVATE, folder / PUBLIC
    if priv.exists() or pub.exists():
        raise FileExistsError(f"já existe um par de chaves em {folder}")
    folder.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    fd = os.open(priv, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(base64.b64encode(_raw_private(key)).decode() + "\n")
    pub.write_text(base64.b64encode(_raw_public(key.public_key())).decode() + "\n")
    return priv, pub


def load_private(path: Path = KEYS / PRIVATE) -> Ed25519PrivateKey:
    if not path.exists():
        raise FileNotFoundError(
            f"sem a chave privada em {path}. Gere com `tool/library_crypto.py gen`."
        )
    return Ed25519PrivateKey.from_private_bytes(base64.b64decode(path.read_text()))


def _content_key(public: bytes, salt: bytes) -> bytes:
    return HKDF(hashes.SHA256(), 32, salt, INFO).derive(public)


def seal(zip_bytes: bytes, private: Ed25519PrivateKey) -> bytes:
    """Cifra [zip_bytes] e assina o resultado."""
    public = _raw_public(private.public_key())
    salt, nonce = os.urandom(32), os.urandom(12)
    header = MAGIC + bytes([VERSION]) + salt + nonce
    cipher = AESGCM(_content_key(public, salt)).encrypt(nonce, zip_bytes, header)
    body = header + cipher
    return body + private.sign(body)


def open_sealed(data: bytes, public: bytes) -> bytes:
    """Confere a assinatura e decifra (o que o app faz). ValueError se falhar."""
    if len(data) < HEADER + 16 + 64 or data[:4] != MAGIC or data[4] != VERSION:
        raise ValueError("não é um envelope zywny")
    body, signature = data[:-64], data[-64:]
    try:
        Ed25519PublicKey.from_public_bytes(public).verify(signature, body)
    except InvalidSignature:
        raise ValueError("assinatura inválida") from None
    salt, nonce = body[5:37], body[37:HEADER]
    return AESGCM(_content_key(public, salt)).decrypt(nonce, body[HEADER:], body[:HEADER])


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["gen"]:
        priv, pub = generate_keys(Path(args[1]) if len(args) > 1 else KEYS)
        print(f"privada: {priv}\npública: {pub}\nGuarde cópia da privada fora do repositório.")
        return 0
    if args[:1] == ["open"] and len(args) == 2:
        public = base64.b64decode((KEYS / PUBLIC).read_text())
        plain = open_sealed(Path(args[1]).read_bytes(), public)
        print(f"ok: zip de {len(plain)} bytes")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

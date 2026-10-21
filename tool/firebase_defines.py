#!/usr/bin/env python3
"""A configuração do projeto no Firebase vira flags de build (D03).

O projeto no Firebase (plano Spark) é criado no console; os valores dele
(apiKey, projectId, os app_id do Android e da Web, o OAuth Client ID do
"Desktop" e o server_client_id do Android) ficam em `keys/firebase.json`,
**fora do git** — como as chaves das bibliotecas. Este script lê esse
arquivo e imprime as flags `--dart-define` que o app entende.

    tool/firebase_defines.py [ARQ.json]            imprime as flags
    tool/firebase_defines.py [ARQ.json] --check    diz o que falta

Sem o arquivo (ou sem um valor), a flag correspondente não sai: o app
compila do mesmo jeito e abre **sem** o portão da conta (é assim que os
testes e o roteiro `just telas` rodam).

Os nomes dos valores no JSON e as flags:

    apiKey                 ZYWNY_FIREBASE_API_KEY
    projectId              ZYWNY_FIREBASE_PROJECT_ID
    messagingSenderId      ZYWNY_FIREBASE_MESSAGING_SENDER_ID
    appIdAndroid           ZYWNY_FIREBASE_APP_ID_ANDROID
    appIdWeb               ZYWNY_FIREBASE_APP_ID_WEB
    authDomain             ZYWNY_FIREBASE_AUTH_DOMAIN
    storageBucket          ZYWNY_FIREBASE_STORAGE_BUCKET
    measurementId          ZYWNY_FIREBASE_MEASUREMENT_ID
    googleClientId         ZYWNY_GOOGLE_CLIENT_ID
    googleServerClientId   ZYWNY_GOOGLE_SERVER_CLIENT_ID
"""

import json
import sys
from pathlib import Path

# O valor no JSON e a flag que o app lê.
VALUES = {
    "apiKey": "ZYWNY_FIREBASE_API_KEY",
    "projectId": "ZYWNY_FIREBASE_PROJECT_ID",
    "messagingSenderId": "ZYWNY_FIREBASE_MESSAGING_SENDER_ID",
    "appIdAndroid": "ZYWNY_FIREBASE_APP_ID_ANDROID",
    "appIdWeb": "ZYWNY_FIREBASE_APP_ID_WEB",
    "authDomain": "ZYWNY_FIREBASE_AUTH_DOMAIN",
    "storageBucket": "ZYWNY_FIREBASE_STORAGE_BUCKET",
    "measurementId": "ZYWNY_FIREBASE_MEASUREMENT_ID",
    "googleClientId": "ZYWNY_GOOGLE_CLIENT_ID",
    "googleServerClientId": "ZYWNY_GOOGLE_SERVER_CLIENT_ID",
}

# O que é preciso para cada plataforma (D03): no Android e na Web o SDK do
# Firebase; no desktop, o login pelo navegador do sistema.
OBRIGATORIOS = {
    "android": [
        "apiKey",
        "projectId",
        "messagingSenderId",
        "appIdAndroid",
        "googleServerClientId",
    ],
    "web": ["apiKey", "projectId", "messagingSenderId", "appIdWeb"],
    "desktop": ["apiKey", "googleClientId"],
}


def _le(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with path.open(encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, ValueError) as erro:
        print(f"{path}: não deu para ler ({erro})", file=sys.stderr)
        return {}
    return dados if isinstance(dados, dict) else {}


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    check = "--check" in argv[1:]
    path = Path(args[0]) if args else Path("keys/firebase.json")
    dados = _le(path)

    if check:
        print(f"configuração do Firebase em {path}:")
        if not path.exists():
            print("  o arquivo não existe (o app vai abrir sem o portão)")
        for nome, flag in VALUES.items():
            valor = dados.get(nome)
            if valor:
                print(f"  ok       {nome} -> {flag}")
            else:
                print(f"  faltando {nome} -> {flag}")
        for plataforma, nomes in OBRIGATORIOS.items():
            faltando = [n for n in nomes if not dados.get(n)]
            if faltando:
                print(f"  {plataforma}: falta {', '.join(faltando)}")
            else:
                print(f"  {plataforma}: completa")
        return 0

    flags = []
    for nome, flag in VALUES.items():
        valor = dados.get(nome)
        if valor:
            flags.append(f"--dart-define={flag}={valor}")
    if flags:
        print(" ".join(flags))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

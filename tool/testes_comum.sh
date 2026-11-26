#!/usr/bin/env bash
# Os testes do zywny-comum: o pacote da raiz e depois, juntos, os de packages/ e
# o score_bridge. Cada pacote roda no seu processo (`dart test` nos de Dart puro,
# `flutter test` nos outros), com a saída guardada; no fim sai uma linha por
# pacote e, de quem falhou, a saída inteira. Sai com 1 se algum falhou.
#
# Os pacotes de packages/ são membros do workspace da raiz e dividem o
# package_config dela: o `flutter test` da raiz resolve as dependências primeiro,
# e os de dentro rodam com `--no-pub`, para não resolverem todos ao mesmo tempo.
# O score_bridge e o zywny_clock têm resolução própria.
#
# Usado pelo `just tudo` (zywny-aprendizado) e pelo `just test-comum`
# (zywny-musicas).
set -u

comum="$(cd "$(dirname "$0")/.." && pwd)"
cd "$comum" || exit 1

flutter test || exit 1

logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

pids=()
nomes=()
for p in packages/*/ score_bridge/; do
  [ -d "$p/test" ] || continue
  nome="$(basename "$p")"
  if grep -q "sdk: flutter" "$p/pubspec.yaml"; then
    if grep -q "^resolution: workspace" "$p/pubspec.yaml"; then
      cmd=(flutter test --no-pub)
    else
      cmd=(flutter test)
    fi
  else
    cmd=(dart test)
  fi
  (cd "$p" && "${cmd[@]}") >"$logs/$nome.log" 2>&1 &
  pids+=("$!")
  nomes+=("$nome")
done

falharam=()
for i in "${!pids[@]}"; do
  nome="${nomes[$i]}"
  if wait "${pids[$i]}"; then
    echo "ok     $nome: $(tail -n 1 "$logs/$nome.log")"
  else
    echo "FALHOU $nome"
    falharam+=("$nome")
  fi
done

for nome in "${falharam[@]}"; do
  echo
  echo "=== $nome"
  cat "$logs/$nome.log"
done

[ "${#falharam[@]}" -eq 0 ]

#!/usr/bin/env bash
# Catraca do relógio (CT05a): conta, por arquivo de lib/, as chamadas que leem a
# hora ou o tempo por fora do AppClock (packages/zywny_clock) e garante que elas
# não cresçam. Desenho igual ao da catraca do BLoC (tool/catraca_bloc.sh).
#
#   tool/catraca_relogio.sh <raiz-do-repo> [--gravar]
#
# Conta cinco padrões: DateTime.now( (DT), Stopwatch( (SW), Timer( (TM),
# Timer.periodic( (PER) e Future.delayed( (FD). Confere os .dart de lib/ da raiz,
# de packages/*, de score_bridge/ e de apps/* (sem .dart_tool, build e *.g.dart),
# menos o pacote packages/zywny_clock, contra tool/catraca_relogio.txt, uma linha
# por arquivo com algum contador acima de zero:
#
#   lib/foo/bar.dart DT=0 SW=0 TM=2 PER=1 FD=0
#
# Não contam: as linhas que são só comentário (// ou ///) e as linhas com a marca
# `// relógio: <motivo>`, que é a exceção de quem fica de propósito (um Timer de
# animação que só pinta, por exemplo). O motivo é obrigatório.
#
# Sai com 1 se um arquivo novo aparece com a hora fora do AppClock, ou se um
# contador sobe. Se um contador desce, avisa e sai com 0, pedindo para baixar a
# base com --gravar (a base tem de ser exata: o aviso não quebra o `just
# qualidade`, mas ninguém deve deixar a base para trás). Com --gravar, reescreve
# o registro com os números atuais.

set -euo pipefail

uso() {
  echo "uso: $0 <raiz-do-repo> [--gravar]" >&2
  exit 2
}

gravar=0
raiz=""
for arg in "$@"; do
  case "$arg" in
    --gravar) gravar=1 ;;
    -*) uso ;;
    *)
      [ -z "$raiz" ] || uso
      raiz="$arg"
      ;;
  esac
done
[ -n "$raiz" ] || uso
[ -d "$raiz" ] || { echo "catraca: pasta não existe: $raiz" >&2; exit 2; }
raiz="$(cd "$raiz" && pwd)"
registro="$raiz/tool/catraca_relogio.txt"

# Os .dart de lib/ da raiz, dos pacotes, do score_bridge e dos apps, com o
# caminho relativo à raiz, em ordem. Fica de fora o próprio pacote do relógio.
arquivos() {
  local pasta
  for pasta in "$raiz/lib" "$raiz"/packages/*/lib "$raiz/score_bridge/lib" "$raiz"/apps/*/lib; do
    [ -d "$pasta" ] || continue
    find "$pasta" \( -name .dart_tool -o -name build \) -prune -o \
      -type f -name '*.dart' ! -name '*.g.dart' -print
  done | LC_ALL=C sort | while IFS= read -r f; do
    rel="${f#"$raiz"/}"
    case "$rel" in
      packages/zywny_clock/*) continue ;;
    esac
    echo "$rel"
  done
}

# Quantas vezes o padrão (grep -P) aparece no texto da entrada.
# $1: o padrão.
conta() {
  { grep -o -P -- "$1" || true; } | wc -l | tr -d ' '
}

# Imprime "DT SW TM PER FD" do arquivo $1 (caminho completo). As linhas de
# comentário e as marcadas com `// relógio: <motivo>` não contam.
contadores() {
  local arq="$1" texto
  texto="$({ grep -v -E '^[[:space:]]*//' -- "$arq" || true; } | { grep -v -E '// relógio: *[^[:space:]]' || true; })"
  local dt sw tm per fd
  dt=$(printf '%s\n' "$texto" | conta 'DateTime\.now\(')
  sw=$(printf '%s\n' "$texto" | conta '(?<![A-Za-z0-9_])Stopwatch\(')
  tm=$(printf '%s\n' "$texto" | conta '(?<![A-Za-z0-9_])Timer\(')
  per=$(printf '%s\n' "$texto" | conta 'Timer\.periodic\(')
  fd=$(printf '%s\n' "$texto" | conta '(?<![A-Za-z0-9_])Future(<[^>]*>)?\.delayed\(')
  echo "$dt $sw $tm $per $fd"
}

# Escreve os cinco contadores na ordem DT SW TM PER FD.
formata() {
  printf 'DT=%s SW=%s TM=%s PER=%s FD=%s' "$@"
}

# Estado atual e registrado, por caminho relativo: "DT SW TM PER FD".
declare -A ATU=()
declare -A REG=()

while IFS= read -r rel; do
  read -r dt sw tm per fd <<<"$(contadores "$raiz/$rel")"
  if (( dt + sw + tm + per + fd > 0 )); then
    ATU[$rel]="$dt $sw $tm $per $fd"
  fi
done < <(arquivos)

re='^([^ ]+) DT=([0-9]+) SW=([0-9]+) TM=([0-9]+) PER=([0-9]+) FD=([0-9]+)[ ]*$'
if [ -f "$registro" ]; then
  while IFS= read -r linha || [ -n "$linha" ]; do
    case "$linha" in
      ''|'#'*) continue ;;
    esac
    if [[ ! "$linha" =~ $re ]]; then
      echo "catraca: linha inválida em ${registro#"$raiz"/}: $linha" >&2
      exit 2
    fi
    REG[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]} ${BASH_REMATCH[6]}"
  done < "$registro"
fi

if [ "$gravar" -eq 1 ]; then
  mkdir -p "$(dirname "$registro")"
  tmp="$registro.novo"
  {
    for p in "${!ATU[@]}"; do
      read -r -a av <<<"${ATU[$p]}"
      echo "$p $(formata "${av[@]}")"
    done | LC_ALL=C sort
  } > "$tmp"
  mv "$tmp" "$registro"
  echo "registro gravado: ${#ATU[@]} arquivos em ${registro#"$raiz"/}"
  exit 0
fi

if [ ! -f "$registro" ]; then
  echo "catraca: falta ${registro#"$raiz"/}; rode com --gravar para criá-lo" >&2
  exit 1
fi

# Totais atuais, para a linha de OK e para o aviso.
tot=(0 0 0 0 0)
for p in "${!ATU[@]}"; do
  read -r -a av <<<"${ATU[$p]}"
  for i in 0 1 2 3 4; do
    tot[i]=$(( tot[i] + av[i] ))
  done
done
resumo="$(formata "${tot[@]}")"

mais=()
menos=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  read -r -a rv <<<"${REG[$p]:-0 0 0 0 0}"
  read -r -a av <<<"${ATU[$p]:-0 0 0 0 0}"
  acima=0
  abaixo=0
  for i in 0 1 2 3 4; do
    if (( av[i] > rv[i] )); then acima=1; fi
    if (( av[i] < rv[i] )); then abaixo=1; fi
  done
  detalhe="  $p  registrado: $(formata "${rv[@]}")  agora: $(formata "${av[@]}")"
  if [ "$acima" -eq 1 ]; then mais+=("$detalhe"); fi
  if [ "$abaixo" -eq 1 ]; then menos+=("$detalhe"); fi
done < <(printf '%s\n' "${!ATU[@]}" "${!REG[@]}" | LC_ALL=C sort -u)

if [ ${#mais[@]} -eq 0 ] && [ ${#menos[@]} -eq 0 ]; then
  echo "catraca do relógio ok (${#ATU[@]} arquivos; $resumo)"
  exit 0
fi

status=0
if [ ${#mais[@]} -gt 0 ]; then
  echo "catraca do relógio: hora ou tempo fora do AppClock acima do registro (use o AppClock do zywny_clock, pelo construtor; ou marque a linha com // relógio: <motivo>):"
  printf '%s\n' "${mais[@]}"
  status=1
fi
if [ ${#menos[@]} -gt 0 ]; then
  echo "aviso: há chamadas de relógio a menos do que a base registra (a base ficou para trás). Atualize-a com tool/catraca_relogio.sh <raiz> --gravar. Arquivos:"
  printf '%s\n' "${menos[@]}"
fi
echo "catraca do relógio: $resumo"
exit "$status"

#!/usr/bin/env bash
# Catraca do BLoC (BL01): conta, por arquivo de lib/, o estado que ainda não
# foi para o BLoC e garante que ele não cresça.
#
#   tool/catraca_bloc.sh <raiz-do-repo> [--gravar]
#
# Conta seis padrões: setState( de widget (S), só a chamada do State (ver
# `conta_setstate`); ChangeNotifier com extends ou with (CN); ValueNotifier<
# (VN); ValueListenableBuilder (VLB); StatefulWidget com extends (SW); ListenableBuilder e addListener( (L,
# estado ouvido fora do BLoC; o BL05–BL07 mostrou que faltava). Confere
# os .dart de lib/ da raiz e de packages/*, score_bridge/ e
# apps/* (sem .dart_tool, build e *.g.dart) contra tool/catraca_bloc.txt, uma
# linha por arquivo com algum contador acima de zero:
#
#   lib/foo/foo_screen.dart S=0 CN=0 VN=0 VLB=1 SW=1 L=0 # framework: AnimationController
#
# Sai com 1 se um arquivo passou do registro (estado novo fora do BLoC) ou se
# ficou abaixo dele (o registro tem de ser exato: rode com --gravar). Com
# --gravar, reescreve o registro com os números atuais e mantém os comentários
# `# framework:` das linhas que continuam existindo.

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
registro="$raiz/tool/catraca_bloc.txt"

# Os .dart de lib/ da raiz, dos pacotes, do score_bridge e dos apps, com o
# caminho relativo à raiz, em ordem.
arquivos() {
  local pasta
  for pasta in "$raiz/lib" "$raiz"/packages/*/lib "$raiz/score_bridge/lib" "$raiz"/apps/*/lib; do
    [ -d "$pasta" ] || continue
    find "$pasta" \( -name .dart_tool -o -name build \) -prune -o \
      -type f -name '*.dart' ! -name '*.g.dart' -print
  done | LC_ALL=C sort | while IFS= read -r f; do
    echo "${f#"$raiz"/}"
  done
}

# Quantas vezes o padrão aparece no arquivo (0 se nenhuma).
# $1: modo do grep (-F ou -E); $2: padrão; $3: arquivo.
conta() {
  { grep -o "$1" -e "$2" -- "$3" || true; } | wc -l | tr -d ' '
}

# setState( de widget: só o que é chamada do State. Não conta DiagLog.retrato(
# (outro objeto: ponto antes), _setState( (letra ou sublinhado antes), a
# declaração void setState(, VoidCallback setState( e static ... setState(. E,
# no arquivo sem classe State nem StatefulBuilder, não conta: os stores de
# autenticação chamam o setState herdado de AuthStoreBase, sem ponto, mas não
# são widget.
conta_setstate() {
  local arq="$1"
  if ! grep -q -E '(^|[^A-Za-z0-9_])State<|StatefulBuilder\(' -- "$arq"; then
    echo 0
    return
  fi
  conta -P '(?<![._A-Za-z0-9])(?<!void )(?<!VoidCallback )(?<!static )setState\(' "$arq"
}

# Imprime "S CN VN VLB SW L" do arquivo $1 (caminho completo).
contadores() {
  local arq="$1" s cn vn vlb sw l
  s=$(conta_setstate "$arq")
  cn=$(conta -E '(extends|with) ChangeNotifier\b' "$arq")
  vn=$(conta -F 'ValueNotifier<' "$arq")
  vlb=$(conta -F 'ValueListenableBuilder' "$arq")
  sw=$(conta -E 'extends StatefulWidget\b' "$arq")
  l=$(conta -E 'ListenableBuilder\b|\baddListener\(' "$arq")
  l=$(( l - $(conta -F 'ValueListenableBuilder' "$arq") ))
  echo "$s $cn $vn $vlb $sw $l"
}

# Escreve os seis contadores na ordem S CN VN VLB SW L.
formata() {
  printf 'S=%s CN=%s VN=%s VLB=%s SW=%s L=%s' "$@"
}

# Estado atual e registrado, por caminho relativo: "S CN VN VLB SW L".
declare -A ATU=()
declare -A REG=()
declare -A FW=()

while IFS= read -r rel; do
  read -r s cn vn vlb sw l <<<"$(contadores "$raiz/$rel")"
  if (( s + cn + vn + vlb + sw + l > 0 )); then
    ATU[$rel]="$s $cn $vn $vlb $sw $l"
  fi
done < <(arquivos)

re='^([^ ]+) S=([0-9]+) CN=([0-9]+) VN=([0-9]+) VLB=([0-9]+) SW=([0-9]+)( L=([0-9]+))?[ ]*$'
if [ -f "$registro" ]; then
  while IFS= read -r linha || [ -n "$linha" ]; do
    case "$linha" in
      ''|'#'*) continue ;;
    esac
    fw=""
    if [[ "$linha" == *" # framework:"* ]]; then
      fw="${linha#*" # framework:"}"
      fw="${fw# }"
      linha="${linha%%" # framework:"*}"
    fi
    if [[ ! "$linha" =~ $re ]]; then
      echo "catraca: linha inválida em ${registro#"$raiz"/}: $linha" >&2
      exit 2
    fi
    p="${BASH_REMATCH[1]}"
    REG[$p]="${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]} ${BASH_REMATCH[6]} ${BASH_REMATCH[8]:-0}"
    FW[$p]="$fw"
  done < "$registro"
fi

if [ "$gravar" -eq 1 ]; then
  mkdir -p "$(dirname "$registro")"
  tmp="$registro.novo"
  {
    for p in "${!ATU[@]}"; do
      read -r -a av <<<"${ATU[$p]}"
      linha="$p $(formata "${av[@]}")"
      if [ -n "${FW[$p]:-}" ]; then
        linha="$linha # framework: ${FW[$p]}"
      fi
      echo "$linha"
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

mais=()
menos=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  read -r -a rv <<<"${REG[$p]:-0 0 0 0 0 0}"
  read -r -a av <<<"${ATU[$p]:-0 0 0 0 0 0}"
  acima=0
  abaixo=0
  for i in 0 1 2 3 4 5; do
    if (( av[i] > rv[i] )); then acima=1; fi
    if (( av[i] < rv[i] )); then abaixo=1; fi
  done
  detalhe="  $p  registrado: $(formata "${rv[@]}")  agora: $(formata "${av[@]}")"
  if [ "$acima" -eq 1 ]; then mais+=("$detalhe"); fi
  if [ "$abaixo" -eq 1 ]; then menos+=("$detalhe"); fi
done < <(printf '%s\n' "${!ATU[@]}" "${!REG[@]}" | LC_ALL=C sort -u)

if [ ${#mais[@]} -eq 0 ] && [ ${#menos[@]} -eq 0 ]; then
  echo "catraca ok (${#ATU[@]} arquivos)"
  exit 0
fi

if [ ${#mais[@]} -gt 0 ]; then
  echo "catraca: estado fora do BLoC acima do registro (código novo com setState, ValueNotifier etc. tem de ir para o BLoC):"
  printf '%s\n' "${mais[@]}"
fi
if [ ${#menos[@]} -gt 0 ]; then
  echo "baixe o registro: rode tool/catraca_bloc.sh <raiz> --gravar (estes arquivos ficaram abaixo do registrado):"
  printf '%s\n' "${menos[@]}"
fi
exit 1

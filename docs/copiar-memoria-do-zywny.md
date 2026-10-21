# Copiar a memória do zywny para o zywny-comum

A memória do projeto antigo `zywny` está no servidor do ai-memory (`http://127.0.0.1:49374`), no projeto `zywny`. Estes passos copiam essa memória para o projeto `zywny-comum`. O projeto `zywny` não é alterado.

O que é copiado: as 754 páginas de conteúdo do export (conceitos, decisões, gotchas, notas, procedimentos, regras e resumos de sessão). Título, corpo, tags, tier e tipo são preservados. Não são copiadas as sessões e observações brutas, só as páginas, e metadados de geração como a data original e o `session_id`.

As páginas citam arquivos do repositório `zywny` (como `docs/plano/...`) que não existem aqui. Elas servem como contexto de decisões e aprendizados, não como estado atual do código.

Pré-requisitos: o servidor do ai-memory no ar e o binário em `~/.local/share/ai-memory/native-runner/ai-memory`.

## 1. Ligar o projeto à memória

```bash
cd ~/IdeaProjects/zywny-comum
claude mcp add --transport http ai-memory http://127.0.0.1:49374/mcp
```

Isso grava só a entrada desta pasta no `~/.claude.json` (escopo local).

## 2. Ligar a captura de sessões só neste projeto

Copie o bloco `hooks` de `~/IdeaProjects/zywny/.claude/settings.local.json` para `.claude/settings.local.json` deste projeto:

```bash
cd ~/IdeaProjects/zywny-comum
python3 - <<'EOF'
import json, os

origem = os.path.expanduser('~/IdeaProjects/zywny/.claude/settings.local.json')
destino = '.claude/settings.local.json'

os.makedirs('.claude', exist_ok=True)
dst = {}
if os.path.exists(destino):
    with open(destino) as f:
        dst = json.load(f)
assert 'hooks' not in dst, 'este projeto já tem hooks: confira antes de sobrescrever'
with open(origem) as f:
    dst['hooks'] = json.load(f)['hooks']
with open(destino, 'w') as f:
    json.dump(dst, f, indent=2, ensure_ascii=False)
    f.write('\n')
EOF
```

Não use `ai-memory install-hooks --apply`: ele escreve no `~/.claude/settings.json` global. O `zywny` já tem hooks no próprio projeto, então os eventos dele passariam a ser gravados duas vezes.

Abra uma nova sessão do Claude Code nesta pasta para os hooks carregarem. Depois de uma sessão, `ai-memory doctor` (rodado aqui) deve mostrar o projeto como capturado.

## 3. Exportar a memória do zywny

```bash
mkdir -p ~/ai-memory-copia
~/.local/share/ai-memory/native-runner/ai-memory --data-dir ~/.local/share/ai-memory export-okf \
  --workspace default --project zywny --to ~/ai-memory-copia/zywny-okf.tar.gz
mkdir ~/ai-memory-copia/zywny-export
tar -xzf ~/ai-memory-copia/zywny-okf.tar.gz -C ~/ai-memory-copia/zywny-export
```

`export-okf` só lê o projeto `zywny`. A pasta `zywny-export` precisa ser nova; se já existir, o `mkdir` para e avisa.

## 4. Preparar o Python (uma vez)

O script usa PyYAML. Instale num venv próprio, sem mexer no Python do sistema:

```bash
python3 -m venv ~/ai-memory-copia/venv
~/ai-memory-copia/venv/bin/pip install pyyaml
```

## 5. Salvar o script

Salve o conteúdo do apêndice deste documento em `~/ai-memory-copia/copiar_memoria.py`.

## 6. Conferir o que será copiado

```bash
~/ai-memory-copia/venv/bin/python -I ~/ai-memory-copia/copiar_memoria.py \
  ~/ai-memory-copia/zywny-export zywny-comum --dry-run
```

O esperado é `754 páginas seriam gravadas em zywny-comum`. Não grava nada.

## 7. Copiar

```bash
~/ai-memory-copia/venv/bin/python -I ~/ai-memory-copia/copiar_memoria.py \
  ~/ai-memory-copia/zywny-export zywny-comum
```

São duas chamadas ao servidor por página, em sequência. O script mostra o progresso a cada 50 páginas e termina com o total e a lista de falhas, se houver.

Se uma página com o mesmo caminho já existir no `zywny-comum`, ela é substituída. Por isso o comando pode ser repetido sem criar duplicatas.

## 8. Verificar

```bash
A=~/.local/share/ai-memory/native-runner/ai-memory
$A --data-dir ~/.local/share/ai-memory read-page --workspace default \
  --project zywny-comum --path _rules/teste-verde-so-vale-do-estado-final.md
```

O corpo deve ser igual ao do arquivo `~/ai-memory-copia/zywny-export/_rules/teste-verde-so-vale-do-estado-final.md`. Para testar a busca:

```bash
$A --data-dir ~/.local/share/ai-memory search --workspace default --project zywny-comum "fase"
```

## Desfazer

- Só a cópia: `delete-page --path <caminho> --workspace default --project zywny-comum`, uma página por vez. A lista de caminhos sai do `--dry-run`.
- Não use `purge-project` para isso: ele apaga o projeto inteiro, inclusive as sessões capturadas, e é irreversível.

## Pendências conhecidas

- A cópia é um retrato do export de 2026-10-18. Páginas novas do `zywny` não chegam aqui sozinhas; rode os passos 3 a 7 de novo (o export sobrescreve as mesmas páginas).
- No último status do servidor, a chave do provedor de LLM (`opencode/deepseek-v4-flash`) estava expirada (erro 401). Se a consolidação de sessões em páginas depende dele, renove a chave antes de contar com a captura. `ai-memory llm-test` verifica.

## Apêndice: `copiar_memoria.py`

```python
"""Copia as páginas de um export OKF do ai-memory para outro projeto.

Uso:
    python -I copiar_memoria.py <pasta_extraida> <projeto_destino> [--dry-run] [--limit N]
"""
import argparse
import os
import re
import subprocess
import sys

import yaml

BIN = os.path.expanduser('~/.local/share/ai-memory/native-runner/ai-memory')
DATA = os.path.expanduser('~/.local/share/ai-memory')
WORKSPACE = 'default'

# Manifesto, índice do export, registro do bootstrap e relatório de lint não são memória.
SKIP = {'_meta.md', 'index.md', 'bootstrap.md', os.path.join('_lint', 'report.md')}
VALID_KIND = {'fact', 'rule', 'decision', 'gotcha'}
VALID_TIER = {'working', 'episodic', 'semantic', 'procedural'}
KIND_BY_DIR = {'decisions': 'decision', 'gotchas': 'gotcha', '_rules': 'rule'}

FRONTMATTER = re.compile(r'^---\n(.*?)\n---\n?', re.S)
ANSI = re.compile(r'\x1b\[[0-9;]*m')


def parse_args():
    p = argparse.ArgumentParser(description='Copia páginas de um export OKF para outro projeto.')
    p.add_argument('origem', help='pasta com o export já extraído')
    p.add_argument('destino', help='projeto que vai receber as páginas')
    p.add_argument('--dry-run', action='store_true', help='só mostra o que seria gravado')
    p.add_argument('--limit', type=int, help='grava só as N primeiras páginas (teste)')
    return p.parse_args()


def split(txt):
    m = FRONTMATTER.match(txt)
    if not m:
        return {}, txt
    return yaml.safe_load(m.group(1)) or {}, txt[m.end():]


def paginas(origem):
    for raiz, _, arquivos in os.walk(origem):
        for nome in arquivos:
            if not nome.endswith('.md'):
                continue
            rel = os.path.relpath(os.path.join(raiz, nome), origem)
            if rel not in SKIP:
                yield rel


def gravar(origem, rel, destino):
    with open(os.path.join(origem, rel), encoding='utf-8') as f:
        fm, body = split(f.read())
    top = rel.split(os.sep)[0] if os.sep in rel else ''

    args = [BIN, f'--data-dir={DATA}', 'write-page',
            f'--path={rel}', '--body', '-',
            f'--workspace={WORKSPACE}', f'--project={destino}']
    if fm.get('title'):
        args.append(f'--title={fm["title"]}')
    tier = fm.get('tier')
    if tier in VALID_TIER:
        args.append(f'--tier={tier}')
    kind = fm.get('kind')
    if kind not in VALID_KIND:
        kind = KIND_BY_DIR.get(top)
    if kind:
        args.append(f'--kind={kind}')
    tags = fm.get('tags') or []
    if isinstance(tags, str):
        tags = [tags]
    for tag in tags:
        args.append(f'--tag={tag}')

    r = subprocess.run(args, input=body.lstrip('\n').encode('utf-8'),
                       capture_output=True, timeout=60)
    err = ANSI.sub('', r.stderr.decode('utf-8', 'replace')).strip()
    return r.returncode, err


def main():
    args = parse_args()
    todo = sorted(paginas(args.origem))
    if args.limit:
        todo = todo[:args.limit]

    if args.dry_run:
        print(f'{len(todo)} páginas seriam gravadas em {args.destino}:')
        for rel in todo[:10]:
            print(f'  {rel}')
        if len(todo) > 10:
            print('  ...')
        return

    ok, falhas = 0, []
    for i, rel in enumerate(todo, 1):
        code, err = gravar(args.origem, rel, args.destino)
        if code == 0:
            ok += 1
        else:
            falhas.append((rel, err.splitlines()[-1] if err else f'saída {code}'))
        if i % 50 == 0:
            print(f'{i}/{len(todo)}', flush=True)

    print(f'gravadas: {ok} de {len(todo)} em {args.destino}')
    for rel, msg in falhas:
        print(f'FALHOU {rel}: {msg}')
    sys.exit(1 if falhas else 0)


if __name__ == '__main__':
    main()
```

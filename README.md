# zywny-comum

Núcleo compartilhado pelos dois apps do zywny:

- **zywny-musicas** — bibliotecas `.zywny` (músicas), partitura, treino.
- **zywny-aprendizado** — cursos e lições, exercícios, leitura à vista.

Este repositório não é um app. É o pacote Dart `zywny_comum` (em `lib/`) mais
os pacotes que ele usa:

| Pasta | O que é |
|---|---|
| `lib/` | partitura (`render/`), prática e MIDI (`practice/`, `midi/`), som (`audio/`), configurações (`settings/`), interface (`ui/`), trilha (`trail/`), sobre (`about/`), pacotes recebidos do sistema (`incoming/`) e três telas comuns em `app/` |
| `packages/` | `zywny_music`, `zywny_course_format`, `zywny_audio`, `zywny_midi`, `zywny_library`, `zywny_diag` (workspace Dart) |
| `score_bridge/` | parser do `.vsb` e `ScenePainter` |
| `native/zywny_audio/` | motor de áudio em Rust (`libzywny_audio`) |
| `web_src/` | motor de áudio para a Web (JavaScript) |
| `tool/` | scripts de build do Verovio e do motor de áudio |

## Como os apps usam

Cada app aponta para este repositório com um caminho ao lado dele:

```
../zywny-comum        # este repositório
../verovio_flutter_bridge   # o Verovio (como antes)
```

O `pubspec.yaml` de cada app declara `zywny_comum` e os pacotes que importa
direto (Dart não resolve dependência transitiva em imports). Os scripts de
build leem `ZYWNY_COMUM` (padrão `../zywny-comum`) e escrevem a saída na pasta
do app que os chamou.

## Testes

- `flutter analyze` e `flutter test` na raiz: testes dos widgets e da lógica
  compartilhada (`test/`).
- Dentro de `packages/*` e `score_bridge/`: `flutter test` ou `dart test`,
  conforme o pacote.
- `test/fixtures/*.vsb` e `score_bridge/test/fixtures/` são exportações do
  corpus do Verovio. Ficam versionadas (como no zywny original): um clone
  limpo roda os testes de render e de `score_bridge` sem copiar nada.

## Fontes

As fontes Cormorant Garamond e Instrument Sans ficam em `assets/fonts/` e são
declaradas aqui. Os apps não as redeclaram.

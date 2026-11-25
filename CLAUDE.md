@AGENTS.md

## Obrigatório: o padrão BLoC

**Todo widget usa o padrão BLoC** para tratar eventos e guardar estado, nos três
repositórios (`zywny-comum`, `zywny-aprendizado`, `zywny-musicas`), inclusive os
motores (MIDI, avaliação, som, partitura). Não é opcional nem "quando der": código
novo ou alterado em `lib/` que não siga o BLoC não entra.

- Nada de `setState`, `ChangeNotifier` ou `ValueNotifier` de estado do app em `lib/`;
  importe `package:zywny_bloc/zywny_bloc.dart` (nunca `flutter_bloc` direto).
- Cubit ao lado do widget (`foo_screen.dart`, `foo_cubit.dart`, `foo_state.dart`),
  estado imutável com `Equatable` e `copyWith`, e teste `blocTest` para cada Cubit.
- Efeito colateral (navegar, diálogo, `SnackBar`) em `BlocListener`, nunca no `builder`.
- StatefulWidget só como dono de objeto do framework, sem `setState`, com a marca na
  catraca (`zywny-comum/tool/catraca_bloc.sh`, que roda no `just qualidade`).
- Vale também para subagentes e ferramentas a quem se delega trabalho: diga isso no
  pedido.
- O guia completo: `zywny-aprendizado/docs/refatoracao/BL00-bloc-em-todos-os-widgets.md`
  ("O guia"); o resumo está no `AGENTS.md`.

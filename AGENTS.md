# Regra de trabalho: nada de branch

Este repositório não usa branch. A equipe trabalha **só no `main`**.

- **Não crie branch.** Nada de `git checkout -b`, `git switch -c`, `git branch <nome>` ou `git worktree add`.
- **Não troque de branch.** Nada de `git checkout <outra>` ou `git switch <outra>`.
- **Salve no `main`.** Faça o commit no `main` e envie com `git push origin main`.
- **Confira antes de começar.** `git branch --show-current` tem de mostrar `main`. Se mostrar outro nome, pare e pergunte antes de mexer em qualquer coisa.
- **Na dúvida, pergunte.** Se o trabalho parecer pedir uma branch ou um pull request, pergunte antes; não crie.

# Regra de projeto: estado e eventos pelo BLoC

Todo widget dos três repositórios (`zywny-comum`, `zywny-aprendizado`, `zywny-musicas`)
trata eventos e guarda estado pelo BLoC, inclusive os motores (MIDI, avaliação, som,
partitura). O guia completo, com as regras dos motores, está em
`zywny-aprendizado/docs/refatoracao/BL00-bloc-em-todos-os-widgets.md` ("O guia").

- **Nenhum `setState`, `ChangeNotifier` ou `ValueNotifier` de estado do app em `lib/`.**
  Importe `package:zywny_bloc/zywny_bloc.dart` (nunca `flutter_bloc` direto).
- **Cubit é o padrão**, ao lado do widget (`foo_screen.dart`, `foo_cubit.dart`,
  `foo_state.dart`); estado imutável com `Equatable` e `copyWith`. Cada Cubit tem o seu
  teste com `blocTest`.
- **StatefulWidget só** como dono de objeto do framework (`AnimationController`, `Ticker`,
  `TextEditingController`, `ScrollController`, `FocusNode`, `WidgetsBindingObserver`,
  `GlobalKey`…) ou de um Cubit que as ações da tela chamam, e sem `setState`.
- **O widget recebe pelo construtor o máximo que puder** (dados, serviços, relógio,
  motores, stores) e o repassa ao Cubit no `BlocProvider(create:)`; nada de buscar
  dependência na árvore (`RepositoryProvider`, `context.read<Serviço>()`) quando ela
  pode vir pelo construtor. Pela árvore só o Cubit da tela e o que é do framework.
- **Efeito colateral** (navegar, diálogo, `SnackBar`) em `BlocListener`, nunca no `builder`.
- **Motores:** métodos síncronos; o motor lê o `state` direto; `serial` no estado quando um
  aviso tem de repetir o mesmo valor; `BlocSelector` onde o motor emite por tique;
  `BlocRepaint` para `CustomPainter(repaint:)`; aviso de motor para motor por chamada
  síncrona (o `stream` é só para a tela); nada de `emit` depois de `close`.
- **Catraca:** `zywny-comum/tool/catraca_bloc.sh <repo>` roda no `just qualidade` e
  compara com `tool/catraca_bloc.txt`, que só tem linhas `# framework: …`. Arquivo novo
  com `setState`/`ValueNotifier`/`ListenableBuilder` quebra a catraca; um dono de objeto
  do framework entra com a marca e o motivo.

# Regra de trabalho: nada de branch

Este repositório não usa branch. A equipe trabalha **só no `main`**.

- **Não crie branch.** Nada de `git checkout -b`, `git switch -c`, `git branch <nome>` ou `git worktree add`.
- **Não troque de branch.** Nada de `git checkout <outra>` ou `git switch <outra>`.
- **Salve no `main`.** Faça o commit no `main` e envie com `git push origin main`.
- **Confira antes de começar.** `git branch --show-current` tem de mostrar `main`. Se mostrar outro nome, pare e pergunte antes de mexer em qualquer coisa.
- **Na dúvida, pergunte.** Se o trabalho parecer pedir uma branch ou um pull request, pergunte antes; não crie.

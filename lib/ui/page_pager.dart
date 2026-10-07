import 'package:flutter/material.dart';

import 'theme.dart';

/// Os botões de página da partitura parada, um em cada canto de baixo da
/// pauta — `‹` à esquerda, `2 / 5 ›` à direita —, para o meio ficar livre.
/// Só aparecem quando a pessoa está só olhando (sem treino nem música
/// tocando) e a música tem mais de uma página.
class PagePager extends StatelessWidget {
  const PagePager({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  /// Índice da página de agora (0 é a primeira).
  final int page;
  final int pageCount;

  /// `null` desabilita o botão (primeira/última página, ou gravando).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // Uma linha da largura da pauta só com os dois cantos: o vão do meio
    // não é de ninguém, e o toque passa para a partitura.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Corner(
          child: IconButton(
            tooltip: 'Página anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
        ),
        const Spacer(),
        _Corner(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  '${page + 1} / $pageCount',
                  style: const TextStyle(fontSize: 14, color: kInkCaption),
                ),
              ),
              IconButton(
                tooltip: 'Próxima página',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: kSurface.withValues(alpha: 0.92),
    elevation: 2,
    shape: const StadiumBorder(side: BorderSide(color: kBorderSoft)),
    child: child,
  );
}

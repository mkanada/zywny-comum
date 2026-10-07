import 'package:flutter/material.dart';

import 'theme.dart';

/// Os botões de página da partitura parada: `‹  2 / 5  ›`, uma pílula à
/// vista no pé da pauta. Só aparece quando a pessoa está só olhando (sem
/// treino nem música tocando) e a música tem mais de uma página.
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
    return Material(
      color: kSurface.withValues(alpha: 0.92),
      elevation: 2,
      shape: const StadiumBorder(side: BorderSide(color: kBorderSoft)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Página anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${page + 1} / $pageCount',
            style: const TextStyle(fontSize: 14, color: kInkCaption),
          ),
          IconButton(
            tooltip: 'Próxima página',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

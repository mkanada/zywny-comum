import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// A faixa da revisão do treino, no pé da partitura. Antes de abrir a
/// revisão oferece "Revisar"; aberta, anda pelas páginas que têm notas
/// erradas e lembra o que o lado da nota quer dizer.
class ReviewBar extends StatelessWidget {
  const ReviewBar({
    super.key,
    required this.count,
    required this.reviewing,
    required this.hasSides,
    required this.onReview,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  /// Quantas notas o treino tem para rever (erradas ou fora do tempo).
  final int count;
  final bool reviewing;

  /// Alguma foi tocada antes ou depois do tempo (tempo real): só então a
  /// legenda de esquerda/direita faz sentido.
  final bool hasSides;
  final VoidCallback onReview;

  /// Pula para a página anterior/seguinte que tem nota errada; `null`
  /// quando não há.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final what = count == 1 ? '1 nota para rever' : '$count notas para rever';
    return Material(
      color: kSurface.withValues(alpha: 0.95),
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reviewing) ...[
              IconButton(
                tooltip: 'Página com erro anterior',
                onPressed: onPrevious,
                icon: const Icon(Icons.keyboard_double_arrow_left),
              ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revisão · $what',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasSides)
                      const Text(
                        'à esquerda da nota: antes do tempo · à direita: depois',
                        style: TextStyle(fontSize: 12, color: kInkCaption),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Próxima página com erro',
                onPressed: onNext,
                icon: const Icon(Icons.keyboard_double_arrow_right),
              ),
            ] else ...[
              Flexible(
                child: Text(
                  what,
                  style: const TextStyle(fontSize: 14, color: kInkCaption),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onReview,
                child: const Text('Revisar'),
              ),
            ],
            IconButton(
              tooltip: reviewing ? 'Fechar a revisão' : 'Dispensar',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

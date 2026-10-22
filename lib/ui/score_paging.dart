// A virada de página da partitura, igual em todos os apps: os botões de
// canto (parada à vista) e os números da virada com a haste (tocando).
import 'package:flutter/material.dart';
import 'package:score_bridge/score_bridge.dart';

import 'page_pager.dart';

/// Como a página vira num `ScoreView` paginado: a largura da haste, o
/// desfoque da página nova e a duração da varredura.
///
/// A página nova entra um pouco fora de foco até a haste sair. No treino com
/// tempo ([timed]) não há desfoque (o aluno precisa ler o que vem antes de
/// tocar) e a virada é curta: 300 ms de parede, em qualquer andamento
/// ([speed]; o teto do `ScoreView` é em ms musicais).
class ScorePageTurn {
  const ScorePageTurn({
    required this.barWidth,
    this.timed = false,
    this.speed = 1.0,
  });

  /// Com a haste padrão do documento (um quarto da largura preta).
  factory ScorePageTurn.of(
    VsbDocument document, {
    bool timed = false,
    double speed = 1.0,
  }) => ScorePageTurn(
    barWidth: defaultBarWidth(document) / 4,
    timed: timed,
    speed: speed,
  );

  final double barWidth;
  final bool timed;
  final double speed;

  double get revealBlurSigma => timed ? 0 : barWidth * 2;

  Duration get maxSweepDuration => timed
      ? Duration(milliseconds: (300 * speed).round())
      : kDefaultMaxSweepDuration;
}

/// Os botões de página ligados a um [ScoreViewController]: somem enquanto a
/// música toca ou treina ([animated]: a haste vira a página) e quando só há
/// uma página. [enabled] `false` (gravando) desabilita os dois.
class ScorePager extends StatelessWidget {
  const ScorePager({
    super.key,
    required this.controller,
    required this.pageCount,
    this.animated = false,
    this.enabled = true,
  });

  final ScoreViewController controller;
  final int pageCount;
  final bool animated;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (animated || pageCount < 2) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ok = enabled && controller.isAttached;
        final page = ok ? controller.currentPage : 0;
        return PagePager(
          onPrevious: ok && page > 0
              ? () => controller.previousPage(animate: false)
              : null,
          onNext: ok && page < pageCount - 1
              ? () => controller.nextPage(animate: false)
              : null,
        );
      },
    );
  }
}

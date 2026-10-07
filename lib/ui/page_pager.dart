import 'package:flutter/material.dart';

import 'theme.dart';

/// Os botões de página da partitura parada: um quarto de círculo em cada
/// canto de baixo da pauta, `‹` na esquerda e `›` na direita, só com a
/// seta — o meio fica livre. Só aparecem quando a pessoa está só olhando
/// (sem treino nem música tocando) e a música tem mais de uma página.
class PagePager extends StatelessWidget {
  const PagePager({super.key, required this.onPrevious, required this.onNext});

  /// `null` desabilita o botão (primeira/última página, ou gravando).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // Uma linha da largura da pauta só com as duas bordas: o vão do meio
    // não é de ninguém, e o toque passa para a partitura.
    return Row(
      children: [
        _HalfCircle(
          tooltip: 'Página anterior',
          icon: Icons.chevron_left,
          onPressed: onPrevious,
          onLeft: true,
        ),
        const Spacer(),
        _HalfCircle(
          tooltip: 'Próxima página',
          icon: Icons.chevron_right,
          onPressed: onNext,
          onLeft: false,
        ),
      ],
    );
  }
}

/// Lado do quarto de círculo (o raio): o canto da tela é o centro do arco.
const double kPagerSize = 52;

class _HalfCircle extends StatelessWidget {
  const _HalfCircle({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.onLeft,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// No canto esquerdo de baixo ou no direito.
  final bool onLeft;

  @override
  Widget build(BuildContext context) {
    // Só o canto de dentro é arredondado; os dois lados retos ficam na borda
    // da tela e o canto da tela é o centro do arco.
    const radius = Radius.circular(kPagerSize);
    final shape = RoundedRectangleBorder(
      borderRadius: onLeft
          ? const BorderRadius.only(topRight: radius)
          : const BorderRadius.only(topLeft: radius),
      side: const BorderSide(color: kBorderSoft),
    );
    return Material(
      color: kSurface.withValues(alpha: 0.92),
      elevation: 2,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        // A seta fica junto do canto, onde o arco tem mais corpo e o polegar
        // chega.
        alignment: onLeft ? Alignment.bottomLeft : Alignment.bottomRight,
        padding: EdgeInsets.only(
          left: onLeft ? 6 : 0,
          right: onLeft ? 0 : 6,
          bottom: 6,
        ),
        constraints: const BoxConstraints.tightFor(
          width: kPagerSize,
          height: kPagerSize,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'theme.dart';

/// Controle segmentado (pílulas dentro de uma trilha cinza) — usado tanto
/// no painel de opções (`OptionsPanel`) quanto na barra de transporte larga
/// (`practice_wide.dart`, telas de desktop/tablet).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.stretch = true,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// `true` (padrão): cada botão ocupa a mesma largura, preenchendo a
  /// trilha — como MODO/MÃO no painel de opções (`flex-grow:1` no
  /// artboard). `false`: cada botão abraça seu texto — como MÃO na barra
  /// de transporte larga (`Main.dc.html`, sem `flex-grow`).
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kChipBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            _wrap(
              _SegmentButton(
                label: labelOf(option),
                selected: option == value,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) => stretch ? Expanded(child: child) : child;
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: selected ? kSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: selected ? 1 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 32,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? kInk : kInkCaption,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

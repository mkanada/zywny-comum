import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// O botão de abrir a revisão nos resumos (da etapa e do treino livre) e,
/// com notas fora do tempo ([hasSides]), o que o lado da fantasma quer
/// dizer — a partitura em revisão não tem legenda própria.
List<Widget> reviewButton({
  required bool hasSides,
  required VoidCallback onPressed,
}) => [
  OutlinedButton(onPressed: onPressed, child: const Text('Rever na partitura')),
  if (hasSides)
    const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        'Na partitura, a nota tocada antes do tempo fica à esquerda da '
        'certa; a tocada depois, à direita.',
        style: TextStyle(fontSize: 12, color: kInkCaption),
        textAlign: TextAlign.center,
      ),
    ),
];

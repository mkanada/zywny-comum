import 'package:flutter/material.dart';

import 'theme.dart';

/// Legenda das cores do treino (U08): uma bolinha e uma palavra por cor, com
/// as cores **de agora** (o aluno as troca nas configurações). Cor sozinha
/// não basta para ninguém decorar; este é o lugar onde se consulta.
class PracticeLegend extends StatelessWidget {
  const PracticeLegend({
    super.key,
    required this.pending,
    required this.correct,
    required this.offBeat,
    required this.wrong,
    required this.missed,
  });

  final Color pending;
  final Color correct;
  final Color offBeat;
  final Color wrong;
  final Color missed;

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11.5, color: kInkCaption)),
      ],
    );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(pending, 'esperada'),
        item(correct, 'certa'),
        item(offBeat, 'fora do tempo'),
        item(wrong, 'errada'),
        item(missed, 'perdida'),
      ],
    );
  }
}

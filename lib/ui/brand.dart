import 'package:flutter/material.dart';

/// A marca do Zywny: o vinho, o creme e o dourado da abertura (splash), os
/// dois tipos e o Z itálico do ícone. Mora em `ui/` porque a abertura e a
/// tela "Sobre o Zywny" usam as mesmas.
const kBrandWine = Color(0xFF5A1E2B);
const kBrandCream = Color(0xFFF4EEE1);
const kBrandGold = Color(0xFFC8A45A);

/// Creme mais apagado: o lema e o crédito sobre o vinho.
const kBrandSoft = Color(0xFFE6DFD0);
const kBrandMuted = Color(0xFFD9D2C3);

const kBrandSerif = 'Cormorant Garamond';
const kBrandSans = 'Instrument Sans';

/// O Z itálico do ícone, em creme.
class MonogramZ extends StatelessWidget {
  const MonogramZ({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'Z',
    style: TextStyle(
      fontFamily: kBrandSerif,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 0.8,
      color: kBrandCream,
      decoration: TextDecoration.none,
    ),
  );
}

// Desenho de runs de texto comum (R04b, §5.4).
//
// A família vem de [resolveFamily] (R04a) e a cor, do chamador (explícita
// do run ou herdada do ancestral — texto herda como qualquer forma).
library;

import 'package:flutter/widgets.dart';

import 'model.dart';
import 'text_font.dart';

/// Monta o `TextPainter` de um run, já com `layout()` feito (R04c/R04d
/// testam esta função direto, sem `Canvas`).
///
/// `fontSize` vai em unidades de viewBox (é o que `size` já traz); a escala
/// da página é do `Canvas`, nunca do `fontSize` (cf. guarda do critério 3).
/// `height: 1.0` evita line-height extra (o SVG não aplica nenhum) e
/// `textScaler: noScaling` blinda contra a acessibilidade do aparelho.
///
/// A família é usada **sem** `package:`: o carregamento é via
/// [loadScoreFonts] (`FontLoader`, nome puro) em teste/headless e no
/// `compare` — sondado em R04b que `package:` + fonte de `FontLoader` cai
/// em fallback silencioso (8910 px vs 3588 px na string de prova).
TextPainter painterForRun(SceneText run, Color color) {
  return TextPainter(
    text: TextSpan(
      text: run.text,
      style: TextStyle(
        fontFamily: resolveFamily(run.family),
        fontSize: run.size,
        letterSpacing: run.letterSpacing,
        fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        color: color,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
}

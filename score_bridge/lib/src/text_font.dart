// Fonte de texto comum (R04a).
//
// O campo `family` do formato (§5.4) NÃO é nome de fonte instalável: no
// corpus vale só `"Times"` (294 runs, de `FontInfo::GetFaceName()`) ou
// `"Times, serif"` (123 runs, fallback do exportador — o mesmo default do
// `font-family` da raiz `<svg class="definition-scale">`). No SVG de
// referência nenhum `<text>` carrega `font-family`: todos herdam o da raiz
// e o `svg_render` resolve o genérico `serif` com
// `set_serif_family("Liberation Serif")`.
//
// Conclusão: no Flutter, `"Times"`, `"Times, serif"` e qualquer valor
// desconhecido significam a mesma serifada do projeto, Liberation Serif
// (embutida em `fonts/` deste pacote). Usar `family` cru como `fontFamily`
// do `TextStyle` faria o Flutter procurar uma "Times" inexistente e cair no
// fallback do sistema sem avisar — por isso há um ponto único de decisão.
library;

import 'package:flutter/services.dart';

/// Família registrada no `pubspec.yaml` deste pacote (os 4 estilos).
const kScoreTextFamily = 'Liberation Serif';

/// Pacote que contém os assets da fonte (para hosts que preferem
/// `TextStyle(package: ...)` em vez do [loadScoreFonts]).
const kScoreTextFamilyPackage = 'score_bridge';

/// Assets de fonte do pacote, na ordem Regular/Italic/Bold/BoldItalic.
const kScoreFontAssets = [
  'packages/score_bridge/fonts/LiberationSerif-Regular.ttf',
  'packages/score_bridge/fonts/LiberationSerif-Italic.ttf',
  'packages/score_bridge/fonts/LiberationSerif-Bold.ttf',
  'packages/score_bridge/fonts/LiberationSerif-BoldItalic.ttf',
];

/// Resolve o `family` do `.vsb` (§5.4) para a família carregada.
///
/// `"Times"`, `"Times, serif"` e desconhecidos devolvem todos
/// [kScoreTextFamily]: o mapeamento é deliberado (ver comentário acima),
/// nunca `family` cru.
String resolveFamily(String vsbFamily) => kScoreTextFamily;

bool _fontsLoaded = false;

/// Carrega os 4 estilos de [kScoreTextFamily] via [FontLoader] (idempotente
/// por processo; `flutter test` isola um processo por arquivo).
///
/// O motor casa estilo/peso pelos metadados da própria fonte (OS/2), por
/// isso os 4 TTFs entram num único `FontLoader` sem descritores. O
/// `TextPainter` usa a família **sem** `package:` (sondado em R04b:
/// `package:` + fonte de `FontLoader` cai em fallback silencioso);
/// chame aqui em teste/headless e no `compare` antes de renderizar texto.
Future<void> loadScoreFonts() async {
  if (_fontsLoaded) {
    return;
  }
  final loader = FontLoader(kScoreTextFamily);
  for (final asset in kScoreFontAssets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
  _fontsLoaded = true;
}

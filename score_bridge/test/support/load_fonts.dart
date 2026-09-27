// Carregamento explícito das TTFs do pacote em teste/headless (R04a).
//
// O carregador mora em `lib` desde R04b (o app `compare` também o usa);
// este arquivo é só um atalho para os testes de R04a continuarem
// importando do mesmo lugar.
library;

export 'package:score_bridge/src/text_font.dart'
    show kScoreFontAssets, loadScoreFonts;

// O desenho da partitura (o Verovio) conta como trabalho ocupado (CT02): o
// roteiro de capturas espera ele terminar antes de fotografar. É um embrulho
// do renderer de verdade, sem mudar o resultado.

import 'package:zywny_diag/app_busy.dart';

import 'score_renderer.dart';

class BusyScoreRenderer implements ScoreRenderer {
  const BusyScoreRenderer(this.inner, this.busy);

  /// O renderer de verdade (o nativo ou o da Web).
  final ScoreRenderer inner;

  /// O contador que o app compartilha.
  final AppBusy busy;

  @override
  Future<RenderedScore> render(ScoreRenderRequest request) {
    final encerrar = busy.begin('desenho da partitura');
    return inner.render(request).whenComplete(encerrar);
  }
}

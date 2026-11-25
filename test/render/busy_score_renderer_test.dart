import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/render/busy_score_renderer.dart';
import 'package:zywny_comum/render/score_renderer.dart';
import 'package:zywny_diag/app_busy.dart';

/// Um renderer que devolve o que o teste mandar (um erro, aqui: basta para
/// ver quando o trabalho termina sem montar um documento de partitura).
class _Falso implements ScoreRenderer {
  _Falso(this.resposta);

  final Completer<RenderedScore> resposta;

  @override
  Future<RenderedScore> render(ScoreRenderRequest request) => resposta.future;
}

ScoreRenderRequest _pedido() => ScoreRenderRequest(
  source: Uint8List(0),
  fileName: 'teste.musicxml',
  pageWidth: 100,
  pageHeight: 100,
);

void main() {
  test(
    'o desenho fica ocupado enquanto o renderer de verdade trabalha',
    () async {
      final busy = AppBusy();
      final resposta = Completer<RenderedScore>();
      final renderer = BusyScoreRenderer(_Falso(resposta), busy);

      final feito = renderer.render(_pedido());
      expect(busy.pendentes, ['desenho da partitura']);

      resposta.completeError(StateError('o Verovio falhou'));
      await expectLater(feito, throwsStateError);
      expect(busy.isBusy, isFalse);
    },
  );

  test('um desenho que dá erro também libera o app', () async {
    final busy = AppBusy();
    final resposta = Completer<RenderedScore>();
    final renderer = BusyScoreRenderer(_Falso(resposta), busy);

    final feito = renderer.render(_pedido());
    resposta.completeError(const FormatException('partitura ruim'));
    await expectLater(feito, throwsFormatException);
    expect(busy.isBusy, isFalse);
  });
}

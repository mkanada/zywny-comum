// U08 — `ScorePlayer.highlightColorOf`: cor própria por id, no seek e no
// avanço. Usa só o fixture do repositório (não depende do corpus).
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

void main() {
  testWidgets('pinta só os ids que ela escolhe, no seek e no avanço', (
    tester,
  ) async {
    final bytes = File('test/fixtures/r13-um-compasso.vsb').readAsBytesSync();
    final doc = VsbDocument.fromBytes(bytes);
    final controller = ScoreController(document: doc);
    const grey = Color(0xFF8E8E93);
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      release: Duration.zero,
    );
    try {
      player.highlightColorOf = (id) => id == 'm1n1' ? grey : null;

      player.seek(Duration.zero);
      expect(controller.colorOf('m1n1'), grey);

      // Avançando: a nota repetida segue cinza; a seguinte (m2n1, em 4000)
      // fica na cor do destaque.
      player.advance(const Duration(milliseconds: 2001));
      expect(controller.colorOf('m1n1'), grey);
      player.advance(const Duration(milliseconds: 2100));
      expect(controller.colorOf('m2n1'), kDefaultHighlightColor);

      // Sem o retorno, tudo volta ao destaque.
      player.highlightColorOf = null;
      player.seek(Duration.zero);
      expect(controller.colorOf('m1n1'), kDefaultHighlightColor);
    } finally {
      // Antes do fim do teste: os destaques têm animações em curso.
      controller.clearAll();
      player.dispose();
      controller.dispose();
    }
  });
}

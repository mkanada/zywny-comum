// `mergeTiedEntries` / `ScorePlayer(mergeTies: true)`: a cadeia de uma
// ligadura acende inteira no ataque da cabeça e apaga junta no fim — é uma
// tecla só. Sem `mergeTies` o timemap do Verovio vale como veio (cada nota
// da cadeia acende no instante em que está escrita).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final name in ['erik-satie.vsb', 'maple-leaf-rag.vsb', 'mazurka.vsb']) {
    test('$name: cada cadeia acende e apaga numa entrada só', () {
      final doc = _fixture(name);
      final raw = ScoreTimeline(doc).entries;
      final merged = mergeTiedEntries(raw, doc.midi);
      final heads = doc.midi!.notes.where((n) => n.tied.isNotEmpty).toList();
      expect(heads, isNotEmpty);

      expect(merged, hasLength(raw.length));
      int count(List<TimemapEntry> es, bool on) =>
          es.fold(0, (n, e) => n + (on ? e.on : e.off).length);
      // Nada some nem duplica: só muda de entrada.
      expect(count(merged, true), count(raw, true));
      expect(count(merged, false), count(raw, false));

      for (final head in heads) {
        final chain = [head.id, ...head.tied];
        final onAt = [
          for (var i = 0; i < merged.length; i++)
            if (merged[i].on.contains(head.id)) i,
        ];
        expect(onAt, hasLength(1), reason: 'cabeça ${head.id}');
        expect(merged[onAt.single].on, containsAll(chain));
        final rawOn = raw.indexWhere((e) => e.on.contains(head.id));
        expect(merged[onAt.single].tstamp, raw[rawOn].tstamp);

        final offAt = [
          for (var i = 0; i < merged.length; i++)
            if (merged[i].off.contains(head.id)) i,
        ];
        expect(offAt, hasLength(1), reason: 'cabeça ${head.id}');
        expect(merged[offAt.single].off, containsAll(chain));
        // O fim da cadeia é onde a última continuação apagava.
        final rawOff = raw.indexWhere((e) => e.off.contains(chain.last));
        expect(merged[offAt.single].tstamp, raw[rawOff].tstamp);
      }
    });
  }

  test('sem midi.json (ou sem ligadura) devolve as mesmas entradas', () {
    final raw = ScoreTimeline(_fixture('erik-satie.vsb')).entries;
    expect(mergeTiedEntries(raw, null), same(raw));
    expect(
      mergeTiedEntries(raw, VsbMidi(notes: const [], pedal: const [])),
      same(raw),
    );
  });

  test('player: no meio da cadeia, todas as notas dela estão acesas', () {
    final doc = _fixture('erik-satie.vsb');
    final head = doc.midi!.notes.firstWhere((n) => n.tied.length >= 2);
    final chain = [head.id, ...head.tied];
    final raw = ScoreTimeline(doc).entries;
    // Instante dentro da 2ª nota da cadeia: a cabeça já teria apagado e a
    // 3ª ainda não teria acendido.
    final second = raw.firstWhere((e) => e.on.contains(head.tied.first));
    final at = Duration(milliseconds: second.tstamp.round() + 100);

    Set<String> litAt({required bool mergeTies}) {
      final controller = ScoreController(document: doc);
      final player = ScorePlayer(
        document: doc,
        controller: controller,
        mergeTies: mergeTies,
      );
      try {
        player.seek(at);
        return chain.where(controller.isHighlighted).toSet();
      } finally {
        controller.clearAll();
        player.dispose();
        controller.dispose();
      }
    }

    expect(litAt(mergeTies: false), {head.tied.first});
    expect(litAt(mergeTies: true), chain.toSet());

    // Tocando desde a cabeça, a cadeia acende de uma vez.
    final controller = ScoreController(document: doc);
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      mergeTies: true,
    );
    try {
      player.advance(Duration(milliseconds: head.onMs.round() + 1));
      expect(chain.every(controller.isHighlighted), isTrue);
    } finally {
      controller.clearAll();
      player.dispose();
      controller.dispose();
    }
  });
}

// Nota escondida (§11, regras 1-3, L02): a porta Dart tem de bater os vetores
// da referência Python (test/fixtures/sumico/vetores.json): notas, nós
// `chord`, formas de barra e traços apagados, com tolerância de 0,5 unidade de
// viewBox nos números.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _dir = 'test/fixtures/sumico';

/// `"alt0.0"` → `PageRef(0, sequence: 0)`; `0` → `PageRef(0)`.
PageRef pageRefOf(Object pagina) {
  if (pagina is int) return PageRef(pagina);
  final text = pagina as String;
  if (text.startsWith('alt')) {
    final parts = text.substring(3).split('.');
    return PageRef(int.parse(parts[1]), sequence: int.parse(parts[0]));
  }
  return PageRef(int.parse(text));
}

void main() {
  final vectors =
      json.decode(File('$_dir/vetores.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = (vectors['casos'] as List).cast<Map<String, dynamic>>();
  final tolerance = (vectors['tolerancia'] as num).toDouble();
  final docs = <String, VsbDocument>{};

  VsbDocument load(String name) => docs.putIfAbsent(
    name,
    () => VsbDocument.fromBytes(File('$_dir/$name').readAsBytesSync()),
  );

  for (final c in cases) {
    test(c['nome'] as String, () {
      final doc = load(c['vsb'] as String);
      final column = (c['coluna'] as List).cast<String>();
      final hidden = c['escondidas'] == null
          ? column.toSet()
          : (c['escondidas'] as List).cast<String>().toSet();
      final got = doc.hiddenShapesFor(hidden, page: pageRefOf(c['pagina']!));
      final want =
          (c['esperado'] as Map<String, dynamic>)['hidden']
              as Map<String, dynamic>;
      final resumo = c['resumo'] as Map<String, dynamic>;

      expect(got.notes, (want['notes'] as List).cast<String>());
      expect(got.chords, (want['chords'] as List).cast<String>());
      final beams = (want['beams'] as List).cast<Map<String, dynamic>>();
      expect(got.beams.length, beams.length);
      for (var i = 0; i < beams.length; i++) {
        expect(got.beams[i].id, beams[i]['id']);
        expect(got.beams[i].shapes, beams[i]['shapes']);
      }
      final ledgers = (want['ledgers'] as List).cast<List<dynamic>>();
      expect(got.ledgers.length, ledgers.length, reason: 'traços');
      for (var i = 0; i < ledgers.length; i++) {
        final w = ledgers[i];
        expect(got.ledgers[i].staff, w[0]);
        expect(got.ledgers[i].side, w[1]);
        expect(got.ledgers[i].k, w[2]);
        expect(got.ledgers[i].x1, closeTo((w[3] as num).toDouble(), tolerance));
        expect(got.ledgers[i].x2, closeTo((w[4] as num).toDouble(), tolerance));
      }

      // O `resumo` à mão tem de bater exatamente.
      expect(got.notes.length, resumo['notes']);
      expect(got.chords.length, resumo['chords']);
      expect(got.beams.length, resumo['beams']);
      expect(got.ledgers.length, resumo['ledgers']);
      // As folhas a apagar: uma por forma de barra e por traço.
      final shapeCount =
          got.beams.fold<int>(0, (s, b) => s + b.shapes) + got.ledgers.length;
      expect(got.leaves.length, shapeCount);
    });
  }
}
